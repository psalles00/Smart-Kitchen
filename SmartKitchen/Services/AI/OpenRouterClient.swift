import Foundation

/// Minimal client for OpenRouter (https://openrouter.ai). The wire format is
/// OpenAI-compatible so we reuse the same `[String: Any]` message shape used
/// by `AIService` and `NutritionAIService`.
///
/// Used as a cloud fallback when OpenAI fails or its key is missing.
@MainActor
final class OpenRouterClient {
    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// Default model for chat/tool-calling (text). Vision uses the same model
    /// since `google/gemini-3-flash` is multimodal.
    private let defaultModel: String

    init(model: String = OpenRouterModel.default) {
        self.defaultModel = model
    }

    // MARK: - Chat (with optional tools)

    /// OpenAI-compatible chat completion against OpenRouter.
    /// - Parameters:
    ///   - messages: same shape used by OpenAI (`[{role, content, ...}]`).
    ///   - tools: optional OpenAI-style tool definitions.
    ///   - apiKey: OpenRouter key (`sk-or-v1-...`).
    func sendChat(
        messages: [[String: Any]],
        tools: [[String: Any]]? = nil,
        apiKey: String,
        model: String? = nil
    ) async throws -> ChatCompletionResponse {
        guard !apiKey.isEmpty else { throw AIError.missingAPIKey }

        var body: [String: Any] = [
            "model": model ?? defaultModel,
            "messages": messages
        ]
        if let tools, !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // Optional but recommended by OpenRouter for ranking / attribution.
        request.setValue("https://smartkitchen.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Savoria", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: request)

        guard let http = resp as? HTTPURLResponse else { throw AIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw AIError.apiError(statusCode: http.statusCode, message: msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw AIError.invalidResponse
        }

        let content = message["content"] as? String
        var toolCalls: [ToolCallRequest] = []
        if let raw = message["tool_calls"] as? [[String: Any]] {
            for tc in raw {
                guard let id = tc["id"] as? String,
                      let function = tc["function"] as? [String: Any],
                      let name = function["name"] as? String,
                      let argsString = function["arguments"] as? String else { continue }
                toolCalls.append(ToolCallRequest(id: id, name: name, argumentsJSON: argsString))
            }
        }
        return ChatCompletionResponse(content: content, toolCalls: toolCalls)
    }

    // MARK: - Vision

    /// Vision request (image + prompt). Returns the assistant's plain-text content
    /// (typically a JSON blob — caller is responsible for parsing).
    func analyzeImage(
        prompt: String,
        imageData: Data,
        apiKey: String,
        model: String? = nil,
        maxTokens: Int = 1024
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw AIError.missingAPIKey }

        let dataURL = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        let body: [String: Any] = [
            "model": model ?? defaultModel,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image_url", "image_url": ["url": dataURL]],
                    ["type": "text", "text": prompt]
                ]
            ]],
            "max_tokens": maxTokens
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://smartkitchen.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Savoria", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw AIError.apiError(statusCode: (resp as? HTTPURLResponse)?.statusCode ?? 0, message: msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty
        else {
            throw AIError.invalidResponse
        }
        return content
    }
}
