import Foundation

enum APIConfig {
    static var openAIAPIKey: String {
        value(for: "OPENAI_API_KEY")
    }

    static var openRouterAPIKey: String {
        value(for: "OPENROUTER_API_KEY")
    }

    static var exaAPIKey: String {
        value(for: "EXA_API_KEY")
    }

    static var supabaseURL: String {
        value(for: "SUPABASE_URL")
    }

    static var supabaseAnonKey: String {
        value(for: "SUPABASE_ANON_KEY")
    }

    private static func value(for key: String) -> String {
#if DEBUG
        ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
#else
        ""
#endif
    }
}