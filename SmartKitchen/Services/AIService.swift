import Foundation
import SwiftData

/// Lightweight chat client that prefers the Supabase Edge Function proxy and
/// falls back to direct OpenAI only for local debug usage.
@MainActor
final class AIService: ObservableObject {
    @Published var isLoading = false

    private let directEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let model = "gpt-4.1-mini"

    // MARK: - Public

    /// Send messages (with optional tools) and receive a streamed or non-streamed reply.
    /// Returns the assistant's content and any tool-call requests.
    func sendChat(
        messages: [[String: Any]],
        tools: [[String: Any]]? = nil,
        apiKey: String
    ) async throws -> ChatCompletionResponse {
        if let proxyURL = APIConfig.secureAIProxyURL, !APIConfig.supabaseAnonKey.isEmpty {
            let proxyBody = try requestBodyData(messages: messages, tools: tools, includeModel: false)
            return try await performRequest(
                url: proxyURL,
                headers: [
                    "Content-Type": "application/json",
                    "apikey": APIConfig.supabaseAnonKey,
                    "Authorization": "Bearer \(APIConfig.supabaseAnonKey)"
                ],
                bodyData: proxyBody
            )
        }

        guard !apiKey.isEmpty else { throw AIError.missingAPIKey }

        let directBody = try requestBodyData(messages: messages, tools: tools, includeModel: true)
        return try await performRequest(
            url: directEndpoint,
            headers: [
                "Content-Type": "application/json",
                "Authorization": "Bearer \(apiKey)"
            ],
            bodyData: directBody
        )
    }

    private func requestBodyData(
        messages: [[String: Any]],
        tools: [[String: Any]]?,
        includeModel: Bool
    ) throws -> Data {
        var body: [String: Any] = [
            "messages": messages
        ]

        if includeModel {
            body["model"] = model
        }

        if let tools, !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }

        return try JSONSerialization.data(withJSONObject: body)
    }

    private func performRequest(
        url: URL,
        headers: [String: String],
        bodyData: Data
    ) async throws -> ChatCompletionResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = 60

        for (header, value) in headers {
            request.setValue(value, forHTTPHeaderField: header)
        }

        isLoading = true
        defer { isLoading = false }

        let (responseData, httpResponse) = try await URLSession.shared.data(for: request)

        guard let http = httpResponse as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let errorBody = String(data: responseData, encoding: .utf8) ?? ""
            throw AIError.apiError(statusCode: http.statusCode, message: errorBody)
        }

        return try parseChatCompletionResponse(from: responseData)
    }

    private func parseChatCompletionResponse(from responseData: Data) throws -> ChatCompletionResponse {
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
            return APIConfig.missingSecureConfigurationMessage
        case .invalidResponse:
            return "Resposta inválida do servidor."
        case .apiError(let code, let msg):
            return "Erro da API (\(code)): \(msg)"
        }
    }
}
