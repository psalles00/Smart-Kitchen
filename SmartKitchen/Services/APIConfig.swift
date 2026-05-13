import Foundation

/// Central API configuration.
/// IMPORTANT: Do NOT hard-code secrets. Load from environment or secure storage.
enum APIConfig {
    static var openAIAPIKey: String {
        return ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    }
}
