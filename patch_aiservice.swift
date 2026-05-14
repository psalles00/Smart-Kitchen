import Foundation

func patchAIService() {
    let servicePath = "SmartKitchen/Services/AIService.swift"
    do {
        var content = try String(contentsOfFile: servicePath, encoding: .utf8)
        
        let oldSendChat = """
        // 1. Try OpenAI (if a key is configured).
        if !apiKey.isEmpty {
            do {
                return try await sendChatOpenAI(messages: messages, tools: tools, apiKey: apiKey, modelOverride: nil, temperature: nil, responseFormat: nil, acceptLanguage: nil, maxTokens: nil)
            } catch {
                LLMLog.error("OpenAI chat failed, falling back to OpenRouter: \\(error.localizedDescription)")
                // fall through to OpenRouter
            }
        } else {
            LLMLog.info("OpenAI key empty; trying OpenRouter directly")
        }

        // 2. Try OpenRouter.
        let orKey = APIConfig.openRouterAPIKey
        guard !orKey.isEmpty else {
            // No fallback key configured — surface the original error semantics.
            throw AIError.missingAPIKey
        }
        LLMLog.info("Routing chat to OpenRouter (\\(OpenRouterModel.default))")
        return try await openRouter.sendChat(messages: messages, tools: tools, apiKey: orKey)
"""
        
        let newSendChat = """
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
                LLMLog.error("OpenAI chat failed, falling back to OpenRouter: \\(error.localizedDescription)")
            }
        }

        // 2. Try OpenRouter.
        let orKey = APIConfig.openRouterAPIKey
        guard !orKey.isEmpty else {
            throw AIError.missingAPIKey
        }
        return try await openRouter.sendChat(messages: messages, tools: tools, apiKey: orKey)
"""
        
        content = content.replacingOccurrences(of: oldSendChat, with: newSendChat)
        
        let oldSendChat2 = """
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
                LLMLog.error("OpenAI chat (overload) failed, falling back to OpenRouter: \\(error.localizedDescription)")
                // fall through to OpenRouter
            }
        } else {
            LLMLog.info("OpenAI key empty; trying OpenRouter directly (overload)")
        }

        // 2. Try OpenRouter.
        let orKey = APIConfig.openRouterAPIKey
        guard !orKey.isEmpty else {
            throw AIError.missingAPIKey
        }
        LLMLog.info("Routing chat to OpenRouter (overload) (\\(OpenRouterModel.default))")
        return try await openRouter.sendChat(messages: messages, tools: nil, apiKey: orKey)
"""

        let newSendChat2 = """
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
                LLMLog.error("OpenAI chat (overload) failed, falling back to OpenRouter: \\(error.localizedDescription)")
            }
        }

        // 2. Try OpenRouter.
        let orKey = APIConfig.openRouterAPIKey
        guard !orKey.isEmpty else {
            throw AIError.missingAPIKey
        }
        return try await openRouter.sendChat(messages: messages, tools: nil, apiKey: orKey)
"""
        
        content = content.replacingOccurrences(of: oldSendChat2, with: newSendChat2)
        
        let oldNetwork = """
        let data = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \\(apiKey)", forHTTPHeaderField: "Authorization")
        if let acceptLanguage { request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language") }
        request.httpBody = data
        request.timeoutInterval = 60

        let (responseData, httpResponse) = try await URLSession.shared.data(for: request)

        guard let http = httpResponse as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let errorBody = String(data: responseData, encoding: .utf8) ?? ""
            throw AIError.apiError(statusCode: http.statusCode, message: errorBody)
        }
"""
        let newNetwork = """
        let supabase = SupabaseClient()
        let responseData: Data
        
        if supabase.isConfigured {
            responseData = try await supabase.invokeFunctionData(name: "ai-chat", body: body, acceptLanguage: acceptLanguage)
        } else {
            guard !apiKey.isEmpty else { throw AIError.missingAPIKey }
            let data = try JSONSerialization.data(withJSONObject: body)
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \\(apiKey)", forHTTPHeaderField: "Authorization")
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
"""

        content = content.replacingOccurrences(of: oldNetwork, with: newNetwork)
        
        let oldWhisper = """
        let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        let boundary = "Boundary-\\(UUID().uuidString)"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \\(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        // Build multipart body
        var body = Data()
"""
        
        let newWhisper = """
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
            let resultData = try await supabase.invokeFunctionData(name: "ai-transcribe", body: payloadData, contentType: "application/json")
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
        let boundary = "Boundary-\\(UUID().uuidString)"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \\(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        // Build multipart body
        var body = Data()
"""
        content = content.replacingOccurrences(of: oldWhisper, with: newWhisper)

        // Try to replace OpenRouterClient to use supabase as well if we don't have api key. Wait, what about OpenAI error string? 
        // "Chave de API não configurada" - actually if supabase is configured, it will NEVER reach missingAPIKey!
        
        try content.write(toFile: servicePath, atomically: true, encoding: .utf8)
        print("Patched AIService.swift")
    } catch {
        print("Error: \\(error)")
    }
}
patchAIService()
