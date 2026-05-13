import Foundation

/// Central API configuration.
/// IMPORTANT: Do NOT hard-code secrets.
enum APIConfig {
    static var openAIAPIKey: String {
        #if DEBUG
        sanitizedEnvironmentValue(named: "OPENAI_API_KEY")
        #else
        ""
        #endif
    }

    static var supabaseURL: String {
        if let bundleValue = sanitizedBundleValue(named: "SUPABASE_URL") {
            return bundleValue
        }

        #if DEBUG
        return sanitizedEnvironmentValue(named: "SUPABASE_URL")
        #else
        return ""
        #endif
    }

    static var supabaseAnonKey: String {
        if let bundleValue = sanitizedBundleValue(named: "SUPABASE_ANON_KEY") {
            return bundleValue
        }

        #if DEBUG
        return sanitizedEnvironmentValue(named: "SUPABASE_ANON_KEY")
        #else
        return ""
        #endif
    }

    static var secureAIProxyURL: URL? {
        guard !supabaseURL.isEmpty, let baseURL = URL(string: supabaseURL) else {
            return nil
        }

        return baseURL.appendingPathComponent("functions").appendingPathComponent("v1").appendingPathComponent("openai-chat")
    }

    static var hasSecureAIProxyConfiguration: Bool {
        secureAIProxyURL != nil && !supabaseAnonKey.isEmpty
    }

    static var aiFeaturesAvailable: Bool {
        hasSecureAIProxyConfiguration || !openAIAPIKey.isEmpty
    }

    static let missingSecureConfigurationMessage = "Os recursos de IA estão desativados até a conexão segura com o servidor da Supabase ser configurada."

    private static func sanitizedBundleValue(named name: String) -> String? {
        let rawValue = Bundle.main.object(forInfoDictionaryKey: name) as? String
        let cleanedValue = cleaned(rawValue)
        return cleanedValue.isEmpty ? nil : cleanedValue
    }

    private static func sanitizedEnvironmentValue(named name: String) -> String {
        let rawValue = ProcessInfo.processInfo.environment[name]
        return cleaned(rawValue)
    }

    private static func cleaned(_ rawValue: String?) -> String {
        let trimmedValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !trimmedValue.isEmpty, !trimmedValue.hasPrefix("$(") else {
            return ""
        }

        return trimmedValue
    }
}
