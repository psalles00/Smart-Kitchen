import Foundation

/// Minimal client for Exa's `/answer` endpoint (https://exa.ai).
///
/// Used to look up nutritional facts (per-100g) from authoritative sources
/// (Open Food Facts, USDA, TACO/Unicamp). The endpoint returns either a plain
/// answer or a structured object matching `outputSchema`.
@MainActor
final class ExaClient {
    private let endpoint = URL(string: "https://api.exa.ai/answer")!
    private let supabase = SupabaseClient()

    enum ExaError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case apiError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return String(localized: "Chave Exa não configurada.")
            case .invalidResponse: return String(localized: "Resposta inválida do Exa.")
            case .apiError(let code, let msg): return String(localized: "Exa API erro \(code): \(msg)")
            }
        }
    }

    struct AnswerResult {
        /// Either a plain string (when `outputSchema` is nil) or a JSON value
        /// matching the schema. Caller is responsible for casting/decoding.
        let rawAnswer: Any
        let citations: [Citation]
    }

    struct Citation {
        let url: String
        let title: String?
        let publishedDate: String?
    }

    /// POSTs `/answer`. Returns the parsed JSON body.
    /// - Parameters:
    ///   - query: natural language question. Be explicit and include locale.
    ///   - outputSchema: optional JSON Schema (Draft-7) — when set, `rawAnswer`
    ///     is a `[String: Any]` or `[Any]` matching the schema.
    ///   - includeDomains: restrict search to these hosts (recommended for
    ///     nutrition lookups).
    func answer(
        query: String,
        outputSchema: [String: Any]? = nil,
        includeDomains: [String] = [],
        apiKey: String
    ) async throws -> AnswerResult {
        var body: [String: Any] = ["query": query]
        if let outputSchema { body["outputSchema"] = outputSchema }
        if !includeDomains.isEmpty { body["includeDomains"] = includeDomains }

        let data: Data
        let resp: URLResponse
        if supabase.isConfigured {
            data = try await supabase.invokeFunctionData(name: "exa-answer", body: body)
            resp = HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
        } else {
            guard !apiKey.isEmpty else { throw ExaError.missingAPIKey }

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.timeoutInterval = 30
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let result = try await URLSession.shared.data(for: request)
            data = result.0
            resp = result.1
        }

        guard let http = resp as? HTTPURLResponse else { throw ExaError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ExaError.apiError(statusCode: http.statusCode, message: msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExaError.invalidResponse
        }

        let answer: Any = json["answer"] ?? ""
        var citations: [Citation] = []
        if let raw = json["citations"] as? [[String: Any]] {
            citations = raw.map {
                Citation(
                    url: ($0["url"] as? String) ?? "",
                    title: $0["title"] as? String,
                    publishedDate: $0["publishedDate"] as? String
                )
            }
        }

        return AnswerResult(rawAnswer: answer, citations: citations)
    }
}
