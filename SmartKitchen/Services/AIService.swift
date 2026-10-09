import Foundation
import SwiftData

/// Lightweight Chat/Transcription client that routes provider calls through
/// Supabase Edge Functions when available.
@MainActor
final class AIService: ObservableObject {
    @Published var isLoading = false

    private let maxToolCount = 24
    private let chatEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let transcriptionEndpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private let openRouterEndpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let defaultModel = "gpt-4.1-mini"
    private let supabase: any SupabaseFunctionInvoking
    private let urlSession: URLSession
    private let openRouterKey: @MainActor () -> String
    private let prefersDirectOpenRouter: @MainActor () -> Bool

    init(
        supabase: any SupabaseFunctionInvoking = SupabaseClient(),
        urlSession: URLSession = .shared,
        openRouterKey: @escaping @MainActor () -> String = { APIConfig.openRouterAPIKey },
        prefersDirectOpenRouter: @escaping @MainActor () -> Bool = { APIConfig.usesLocalOpenRouter }
    ) {
        self.supabase = supabase
        self.urlSession = urlSession
        self.openRouterKey = openRouterKey
        self.prefersDirectOpenRouter = prefersDirectOpenRouter
    }

    // MARK: - Public

    /// Send messages (with optional tools) and receive a streamed or non-streamed reply.
    /// Returns the assistant's content and any tool-call requests.
    func sendChat(
        messages: [[String: Any]],
        tools: [[String: Any]]? = nil,
        apiKey: String,
        model: String? = nil,
        temperature: Double? = nil,
        responseFormat: [String: Any]? = nil,
        maxTokens: Int? = nil,
        acceptLanguage: String? = nil
    ) async throws -> ChatCompletionResponse {
        let sanitizedTools = sanitizeTools(tools)
        var body: [String: Any] = [
            "model": model ?? defaultModel,
            "messages": messages
        ]
        if let sanitizedTools, !sanitizedTools.isEmpty {
            body["tools"] = sanitizedTools
            body["tool_choice"] = "auto"
        }
        if let temperature {
            body["temperature"] = temperature
        }
        if let responseFormat {
            body["response_format"] = responseFormat
        }
        if let maxTokens {
            body["max_tokens"] = maxTokens
        }

        isLoading = true
        defer { isLoading = false }

        let responseData = try await performJSONRequest(
            functionName: "openai-chat",
            directURL: chatEndpoint,
            body: body,
            apiKey: apiKey,
            acceptLanguage: acceptLanguage
        )

        return try parseChatCompletion(from: responseData)
    }

    func analyzeImage(
        prompt: String,
        imageData: Data,
        apiKey: String,
        model: String,
        maxTokens: Int = 1024,
        acceptLanguage: String? = nil
    ) async throws -> String {
        let dataURL = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        let response = try await sendChat(
            messages: [[
                "role": "user",
                "content": [
                    ["type": "image_url", "image_url": ["url": dataURL]],
                    ["type": "text", "text": prompt]
                ]
            ]],
            apiKey: apiKey,
            model: model,
            maxTokens: maxTokens,
            acceptLanguage: acceptLanguage
        )

        guard let content = response.content, !content.isEmpty else {
            throw AIError.invalidResponse
        }
        return content
    }

    func transcribeAudio(
        fileURL: URL,
        apiKey: String,
        model: String = "whisper-1",
        language: String = "pt",
        responseFormat: String = "text"
    ) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        let audioData = try Data(contentsOf: fileURL)
        var body = Data()

        appendFormField(name: "model", value: model, to: &body, boundary: boundary)
        appendFormField(name: "language", value: language, to: &body, boundary: boundary)
        appendFormField(name: "response_format", value: responseFormat, to: &body, boundary: boundary)
        appendFileField(
            name: "file",
            filename: fileURL.lastPathComponent,
            mimeType: "audio/mp4",
            fileData: audioData,
            to: &body,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        isLoading = true
        defer { isLoading = false }

        let responseData: Data
        if supabase.isConfigured {
            do {
                responseData = try await supabase.invokeFunctionData(
                    name: "openai-transcription",
                    body: body,
                    contentType: "multipart/form-data; boundary=\(boundary)",
                    acceptLanguage: nil
                )
            } catch {
                guard !apiKey.isEmpty else { throw error }
                LLMLog.error("Supabase transcription failed; falling back to direct OpenAI: \(error.localizedDescription)")
                responseData = try await performDirectTranscription(
                    body: body,
                    boundary: boundary,
                    apiKey: apiKey
                )
            }
        } else {
            responseData = try await performDirectTranscription(
                body: body,
                boundary: boundary,
                apiKey: apiKey
            )
        }

        guard let transcript = String(data: responseData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !transcript.isEmpty else {
            throw AIError.invalidResponse
        }

        return transcript
    }

    private func performJSONRequest(
        functionName: String,
        directURL: URL,
        body: [String: Any],
        apiKey: String,
        acceptLanguage: String? = nil
    ) async throws -> Data {
        let sanitizedBody = sanitizeRequestBody(body)

        if prefersDirectOpenRouter(), !openRouterKey().isEmpty {
            return try await performOpenRouterJSONRequest(
                body: sanitizedBody,
                apiKey: openRouterKey(),
                acceptLanguage: acceptLanguage
            )
        }

        if supabase.isConfigured {
            do {
                return try await supabase.invokeFunctionData(
                    name: functionName,
                    body: sanitizedBody,
                    acceptLanguage: acceptLanguage
                )
            } catch {
                guard hasDirectChatBackend(apiKey: apiKey) else { throw error }
                LLMLog.error("Supabase \(functionName) failed; falling back to direct provider: \(error.localizedDescription)")
            }
        }

        return try await performDirectJSONRequest(
            directURL: directURL,
            body: sanitizedBody,
            apiKey: apiKey,
            acceptLanguage: acceptLanguage
        )
    }

    private func performDirectJSONRequest(
        directURL: URL,
        body: [String: Any],
        apiKey: String,
        acceptLanguage: String? = nil
    ) async throws -> Data {
        if !apiKey.isEmpty {
            do {
                return try await performOpenAIJSONRequest(
                    directURL: directURL,
                    body: body,
                    apiKey: apiKey,
                    acceptLanguage: acceptLanguage
                )
            } catch {
                guard !openRouterKey().isEmpty else { throw error }
                LLMLog.error("Direct OpenAI request failed; falling back to OpenRouter: \(error.localizedDescription)")
            }
        }

        guard !openRouterKey().isEmpty else { throw AIError.missingAPIKey }
        return try await performOpenRouterJSONRequest(
            body: body,
            apiKey: openRouterKey(),
            acceptLanguage: acceptLanguage
        )
    }

    private func performOpenAIJSONRequest(
        directURL: URL,
        body: [String: Any],
        apiKey: String,
        acceptLanguage: String? = nil
    ) async throws -> Data {
        guard !apiKey.isEmpty else { throw AIError.missingAPIKey }

        var request = URLRequest(url: directURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let acceptLanguage, !acceptLanguage.isEmpty {
            request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, resp) = try await urlSession.data(for: request)
        try validate(resp: resp, data: data)
        return data
    }

    private func performOpenRouterJSONRequest(
        body: [String: Any],
        apiKey: String,
        acceptLanguage: String? = nil
    ) async throws -> Data {
        var openRouterBody = body
        if let model = openRouterBody["model"] as? String,
           model.hasPrefix("gpt-") || model.hasPrefix("o") {
            openRouterBody["model"] = OpenRouterModel.default
        } else if openRouterBody["model"] == nil {
            openRouterBody["model"] = OpenRouterModel.default
        }

        var request = URLRequest(url: openRouterEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://smartkitchen.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Savoria", forHTTPHeaderField: "X-Title")
        if let acceptLanguage, !acceptLanguage.isEmpty {
            request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: openRouterBody)
        request.timeoutInterval = 60

        let (data, resp) = try await urlSession.data(for: request)
        try validate(resp: resp, data: data)
        return data
    }

    private func performDirectTranscription(
        body: Data,
        boundary: String,
        apiKey: String
    ) async throws -> Data {
        guard !apiKey.isEmpty else { throw AIError.missingAPIKey }

        var request = URLRequest(url: transcriptionEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = body

        let (data, resp) = try await urlSession.data(for: request)
        try validate(resp: resp, data: data)
        return data
    }

    private func hasDirectChatBackend(apiKey: String) -> Bool {
        !apiKey.isEmpty || !openRouterKey().isEmpty
    }

    private func sanitizeTools(_ tools: [[String: Any]]?) -> [[String: Any]]? {
        guard let tools, !tools.isEmpty else {
            return nil
        }

        return Array(tools.prefix(maxToolCount))
    }

    private func sanitizeRequestBody(_ body: [String: Any]) -> [String: Any] {
        guard let rawTools = body["tools"] as? [[String: Any]] else {
            return body
        }

        var sanitizedBody = body
        sanitizedBody["tools"] = Array(rawTools.prefix(maxToolCount))
        return sanitizedBody
    }

    private func parseChatCompletion(from responseData: Data) throws -> ChatCompletionResponse {
        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw AIError.invalidResponse
        }

        let content = message["content"] as? String
        var toolCalls = [ToolCallRequest]()

        if let rawToolCalls = message["tool_calls"] as? [[String: Any]] {
            for tc in rawToolCalls {
                guard let id = tc["id"] as? String,
                      let function = tc["function"] as? [String: Any],
                      let name = function["name"] as? String,
                      let argsString = function["arguments"] as? String else { continue }
                toolCalls.append(ToolCallRequest(id: id, name: name, argumentsJSON: argsString))
            }
        }

        return ChatCompletionResponse(content: content, toolCalls: toolCalls)
    }

    private func validate(resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw AIError.apiError(statusCode: http.statusCode, message: errorBody)
        }
    }

    private func appendFormField(name: String, value: String, to body: inout Data, boundary: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    private func appendFileField(
        name: String,
        filename: String,
        mimeType: String,
        fileData: Data,
        to body: inout Data,
        boundary: String
    ) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
    }

    // MARK: - Conversation Loop

    /// Full conversation loop: sends user message, handles tool calls automatically, returns final content.
    func chat(
        messages: inout [[String: Any]],
        tools: [[String: Any]],
        toolHandler: (ToolCallRequest) async -> String,
        apiKey: String
    ) async throws -> ChatCompletionResponse {
        var response = try await sendChat(messages: messages, tools: tools, apiKey: apiKey)

        // Process tool calls iteratively (max 5 rounds to prevent infinite loops)
        var rounds = 0
        while !response.toolCalls.isEmpty && rounds < 5 {
            rounds += 1

            // Add the assistant's message with tool_calls
            var assistantMsg: [String: Any] = ["role": "assistant"]
            if let content = response.content {
                assistantMsg["content"] = content
            }
            let toolCallsJSON: [[String: Any]] = response.toolCalls.map { tc in
                [
                    "id": tc.id,
                    "type": "function",
                    "function": [
                        "name": tc.name,
                        "arguments": tc.argumentsJSON
                    ]
                ]
            }
            assistantMsg["tool_calls"] = toolCallsJSON
            messages.append(assistantMsg)

            // Execute each tool call and add results
            for tc in response.toolCalls {
                let result = await toolHandler(tc)
                messages.append([
                    "role": "tool",
                    "tool_call_id": tc.id,
                    "content": result
                ])
            }

            // Send again
            response = try await sendChat(messages: messages, tools: tools, apiKey: apiKey)
        }

        return response
    }
}

// MARK: - Types

struct ChatCompletionResponse {
    let content: String?
    let toolCalls: [ToolCallRequest]
}

struct ToolCallRequest: Sendable {
    let id: String
    let name: String
    let argumentsJSON: String

    var arguments: [String: Any] {
        (try? JSONSerialization.jsonObject(
            with: Data(argumentsJSON.utf8)
        ) as? [String: Any]) ?? [:]
    }
}

enum AIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return APIConfig.missingAIConfigurationMessage
        case .invalidResponse:
            return "Resposta inválida do servidor."
        case .apiError(let code, let msg):
            return "Erro da API (\(code)): \(msg)"
        }
    }
}
