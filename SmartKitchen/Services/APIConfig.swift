import Foundation

enum APIConfig {
    static var openAIAPIKey: String {
        debugProviderValue(infoKey: "OpenAIAPIKey", envKey: "OPENAI_API_KEY")
    }

    static var openRouterAPIKey: String {
        debugProviderValue(infoKey: "OpenRouterAPIKey", envKey: "OPENROUTER_API_KEY")
    }

    static var exaAPIKey: String {
        debugProviderValue(infoKey: "ExaAPIKey", envKey: "EXA_API_KEY")
    }

    static var supabaseURL: String {
        bundleValue(infoKey: "SupabaseURL", envKey: "SUPABASE_URL")
    }

    static var supabaseAnonKey: String {
        bundleValue(infoKey: "SupabaseAnonKey", envKey: "SUPABASE_ANON_KEY")
    }

    static var hasSupabaseCredentials: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }

    static var hasAIBackend: Bool {
        hasSupabaseCredentials || !openAIAPIKey.isEmpty || !openRouterAPIKey.isEmpty
    }

    static var hasExaBackend: Bool {
        hasSupabaseCredentials || !exaAPIKey.isEmpty
    }

    private static func bundleValue(infoKey: String, envKey: String) -> String {
        if let rawValue = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.hasPrefix("$(") {
                return trimmed
            }
        }

#if DEBUG
        return ProcessInfo.processInfo.environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
#endif

        return ""
    }

    private static func debugProviderValue(infoKey: String, envKey: String) -> String {
#if DEBUG
        return bundleValue(infoKey: infoKey, envKey: envKey)
#else
        return ""
#endif
    }
}
