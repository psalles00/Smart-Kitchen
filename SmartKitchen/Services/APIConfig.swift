import Foundation

enum APIConfig {
    static var openAIAPIKey: String {
        debugValue(for: "OPENAI_API_KEY")
    }

    static var openRouterAPIKey: String {
        debugValue(for: "OPENROUTER_API_KEY")
    }

    static var exaAPIKey: String {
        debugValue(for: "EXA_API_KEY")
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
            if !trimmed.isEmpty {
                return trimmed
            }
        }

#if DEBUG
        return ProcessInfo.processInfo.environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
#endif

        return ""
    }

    private static func debugValue(for key: String) -> String {
#if DEBUG
        return ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
#else
        return ""
#endif
    }
}