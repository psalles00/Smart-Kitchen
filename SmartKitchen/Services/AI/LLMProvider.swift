import Foundation
import OSLog

/// Identifies which backend handled (or was attempted for) an LLM request.
/// Used purely for logging and diagnostics; not surfaced in the UI.
enum LLMProvider: String, CustomStringConvertible {
    case appleIntelligence
    case openAI
    case openRouter

    var description: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence"
        case .openAI:            return "OpenAI"
        case .openRouter:        return "OpenRouter"
        }
    }
}

/// Capability flags so the router can skip providers that can't satisfy a request.
struct LLMCapabilities: OptionSet {
    let rawValue: Int
    static let toolCalling = LLMCapabilities(rawValue: 1 << 0)
    static let vision      = LLMCapabilities(rawValue: 1 << 1)
}

/// Default OpenRouter model used as cloud fallback. Chosen for good
/// price/quality on text + vision + tool calling.
///
/// If the slug below is rejected by OpenRouter (e.g. naming changed),
/// update here. The key (`OPENROUTER_API_KEY`) lives in `Config/Secrets.xcconfig`.
enum OpenRouterModel {
    static let `default` = "google/gemini-3-flash"
}

/// Lightweight logger for the LLM fallback layer.
enum LLMLog {
    static let logger = Logger(subsystem: "com.pedrosalles.smartkitchen", category: "LLM")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
