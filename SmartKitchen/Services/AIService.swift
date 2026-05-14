import Foundation
import SwiftData

/// Lightweight OpenAI Chat-Completions client with streaming & function-calling support.
///
/// Falls back automatically to OpenRouter (`google/gemini-3-flash` by default) when
/// OpenAI fails for any reason — missing key, network error, 4xx/5xx, rate limit.
/// Apple Intelligence is NOT used here because the chat path requires tool/function
/// calling, which `FoundationModels` does not expose.
@MainActor
final class AIService: ObservableObject {
    @Published var isLoading = false

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let model = "gpt-4.1-mini"
    private let openRouter = OpenRouterClient()

    // MARK: - Public

    /// Send messages (with optional tools) and receive a streamed or non-streamed reply.
    /// Returns the assistant's content and any tool-call requests.
    ///
    /// - Note: `apiKey` is treated as the OpenAI key. If empty or if OpenAI fails for
    /// any reason, this method transparently falls back to OpenRouter using the key
    /// configured in `APIConfig.openRouterAPIKey`.
    func sendChat(
        messages: [[String: Any]],
        tools: [[String: Any]]? = nil,
        apiKey: String
    ) async throws -> ChatCompletionResponse {
        isLoading = true
        defer { isLoading = false }

        let supabase = SupabaseClient()
        if supabase.isConfigured {
            return try await sendChatOpenAI(
                messages: messages,
                tools: tools,
                apiKey: "",
                modelOverride: nil,
                temperature: nil,
                responseFormat: nil,
                acceptLanguage: nil,
                maxTokens: nil
            )
        }

        // 1. Try OpenAI (if a key is configured).
        if !apiKey.isEmpty {
            do {
                return try await sendChatOpenAI(messages: messages, tools: tools, apiKey: apiKey, modelOverride: nil, temperature: nil, responseFormat: nil, acceptLanguage: nil, maxTokens: nil)
            } catch {
                LLMLog.error("OpenAI chat failed, falling back to OpenRouter: \(error.localizedDescription)")
            }
        }

        // 2. Try OpenRouter.
        let orKey = APIConfig.openRouterAPIKey
        guard !orKey.isEmpty else {
            throw AIError.missingAPIKey
        }
        return try await openRouter.sendChat(messages: messages, tools: tools, apiKey: orKey)
    }

    /// Convenience overload that allows specifying model/temperature/response format/accept-language.
    func sendChat(
        messages: [[String: Any]],
        apiKey: String,
        model: String? = nil,
        temperature: Double? = nil,
        responseFormat: [String: Any]? = nil,
        acceptLanguage: String? = nil
    ) async throws -> ChatCompletionResponse {
        isLoading = true
        defer { isLoading = false }

        let supabase = SupabaseClient()
        if supabase.isConfigured {
            return try await sendChatOpenAI(
                messages: messages,
                tools: nil,
                apiKey: "",
                modelOverride: model,
                temperature: temperature,
                responseFormat: responseFormat,
                acceptLanguage: acceptLanguage,
                maxTokens: nil
            )
        }

        // 1. Try OpenAI (if a key is configured).
        if !apiKey.isEmpty {
            do {
                return try await sendChatOpenAI(
                    messages: messages,
                    tools: nil,
                    apiKey: apiKey,
                    modelOverride: model,
                    temperature: temperature,
                    responseFormat: responseFormat,
                    acceptLanguage: acceptLanguage,
                    maxTokens: nil
                )
            } catch {
                LLMLog.error("OpenAI chat (overload) failed, falling back to OpenRouter: \(error.localizedDescription)")
            }
        }

        // 2. Try OpenRouter.
        let orKey = APIConfig.openRouterAPIKey
        guard !orKey.isEmpty else {
            throw AIError.missingAPIKey
        }
        return try await openRouter.sendChat(messages: messages, tools: nil, apiKey: orKey)
    }

    /// Analyze an image with a text prompt using Chat Completions (vision-capable models like gpt-4o-mini).
    func analyzeImage(
        prompt: String,
        imageData: Data,
        apiKey: String,
        model: String,
        maxTokens: Int? = nil,
        acceptLanguage: String? = nil
    ) async throws -> String {
        // Compose a multi-part content array: text + image_url (data URL)
        let b64 = imageData.base64EncodedString()
        let dataURL = "data:image/jpeg;base64,\(b64)"
        let content: [[String: Any]] = [
            ["type": "text", "text": prompt],
            ["type": "image_url", "image_url": ["url": dataURL]]
        ]
        let messages: [[String: Any]] = [["role": "user", "content": content]]
        let response = try await sendChatOpenAI(
            messages: messages,
            tools: nil,
            apiKey: apiKey,
            modelOverride: model,
            temperature: nil,
            responseFormat: nil,
            acceptLanguage: acceptLanguage,
            maxTokens: maxTokens
        )
        guard let contentText = response.content, !contentText.isEmpty else {
            throw AIError.invalidResponse
        }
        return contentText
    }

    // MARK: - OpenAI implementation

    private func sendChatOpenAI(
        messages: [[String: Any]],
        tools: [[String: Any]]?,
        apiKey: String,
        modelOverride: String? = nil,
        temperature: Double? = nil,
        responseFormat: [String: Any]? = nil,
        acceptLanguage: String? = nil,
        maxTokens: Int? = nil
    ) async throws -> ChatCompletionResponse {
        var body: [String: Any] = [
            "model": modelOverride ?? model,
            "messages": messages
        ]
        if let tools, !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }
        if let temperature { body["temperature"] = temperature }
        if let responseFormat { body["response_format"] = responseFormat }
        if let maxTokens { body["max_tokens"] = maxTokens }

        let supabase = SupabaseClient()
        let responseData: Data
        
        if supabase.isConfigured {
            responseData = try await supabase.invokeFunctionData(name: "openai-chat", body: body, acceptLanguage: acceptLanguage)
        } else {
            guard !apiKey.isEmpty else { throw AIError.missingAPIKey }
            let data = try JSONSerialization.data(withJSONObject: body)
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            if let acceptLanguage { request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language") }
            request.httpBody = data
            request.timeoutInterval = 60

            let result = try await URLSession.shared.data(for: request)
            responseData = result.0
            
            guard let http = result.1 as? HTTPURLResponse else {
                throw AIError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                let errorBody = String(data: responseData, encoding: .utf8) ?? ""
                throw AIError.apiError(statusCode: http.statusCode, message: errorBody)
            }
        }

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

    /// Transcribe audio using OpenAI's Whisper endpoint.
    func transcribeAudio(
        fileURL: URL,
        apiKey: String,
        model: String = "whisper-1",
        language: String? = nil,
        responseFormat: String = "text"
    ) async throws -> String {
        let supabase = SupabaseClient()
        if supabase.isConfigured {
            // Se Supabase for configurado, passe o áudio codificado em base64 para a edge function
            let audioData = try Data(contentsOf: fileURL)
            let payload: [String: Any] = [
                "audio_base64": audioData.base64EncodedString(),
                "model": model,
                "language": language ?? "",
                "response_format": responseFormat
            ]
            let payloadData = try JSONSerialization.data(withJSONObject: payload)
            let resultData = try await supabase.invokeFunctionData(name: "openai-transcription", body: payloadData, contentType: "application/json")
            if responseFormat == "text", let text = String(data: resultData, encoding: .utf8) {
                // Remove possible json wrapping if function returns JSON anyway
                if let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any], let t = json["text"] as? String {
                    return t
                }
                return text
            }
            if let json = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any], let text = json["text"] as? String {
                return text
            }
            return String(data: resultData, encoding: .utf8) ?? ""
        }
        
        let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        // Build multipart body
        var body = Data()
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        func appendFileField(name: String, filename: String, mimeType: String, fileData: Data) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
        }

        appendField(name: "model", value: model)
        if let language { appendField(name: "language", value: language) }
        appendField(name: "response_format", value: responseFormat)

        let data = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let ext = fileURL.pathExtension.lowercased()
        let mime: String = {
            switch ext {
            case "m4a": return "audio/m4a"
            case "mp3": return "audio/mpeg"
            case "wav": return "audio/wav"
            case "webm": return "audio/webm"
            case "ogg": return "audio/ogg"
            default: return "application/octet-stream"
            }
        }()
        appendFileField(name: "file", filename: filename.isEmpty ? "audio.m4a" : filename, mimeType: mime, fileData: data)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (responseData, httpResponse) = try await URLSession.shared.data(for: request)
        guard let http = httpResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let errorBody = String(data: responseData, encoding: .utf8) ?? ""
            throw AIError.apiError(statusCode: (httpResponse as? HTTPURLResponse)?.statusCode ?? -1, message: errorBody)
        }

        // For response_format == "text", the body is plain text.
        if responseFormat == "text", let text = String(data: responseData, encoding: .utf8) {
            return text
        }
        // Otherwise, try to decode as JSON and extract the text.
        if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
            if let text = json["text"] as? String { return text }
        }
        // Fallback
        return String(data: responseData, encoding: .utf8) ?? ""
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
            return String(localized: "Chave de API não configurada. Adicione sua chave OpenAI em Ajustes.")
        case .invalidResponse:
            return String(localized: "Resposta inválida do servidor.")
        case .apiError(let code, let msg):
            return String(localized: "Erro da API (\(code)): \(msg)")
        }
    }
}
