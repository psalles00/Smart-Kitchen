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

    static var aiFeaturesAvailable: Bool {
        !openAIAPIKey.isEmpty
    }

    static let missingSecureConfigurationMessage = "Os recursos de IA estão desativados nesta versão até o servidor seguro ficar pronto."

    private static func sanitizedEnvironmentValue(named name: String) -> String {
        let rawValue = ProcessInfo.processInfo.environment[name]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !rawValue.isEmpty, !rawValue.hasPrefix("$(") else {
            return ""
        }

        return rawValue
    }
}
