import Foundation

@MainActor
protocol SupabaseFunctionInvoking {
    var isConfigured: Bool { get }

    func invokeFunctionData(
        name: String,
        body: [String: Any],
        acceptLanguage: String?
    ) async throws -> Data

    func invokeFunctionData(
        name: String,
        body: Data,
        contentType: String,
        acceptLanguage: String?
    ) async throws -> Data
}

/// Lightweight Supabase REST client (PostgREST + RPC) over `URLSession`.
///
/// We deliberately avoid the official `supabase-swift` SDK to keep dependencies
/// minimal — our needs are limited to a couple of GET/POST calls.
///
/// Auth: anon key in `apikey` and `Authorization: Bearer` headers. Access is
/// gated by Row Level Security policies on the server. **Never embed the
/// service_role key in this client.**
@MainActor
final class SupabaseClient: SupabaseFunctionInvoking {
    enum SupabaseError: LocalizedError {
        case notConfigured
        case invalidResponse
        case apiError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return String(localized: "Supabase não configurado (SUPABASE_URL/SUPABASE_ANON_KEY).")
            case .invalidResponse:
                return String(localized: "Resposta inválida do Supabase.")
            case .apiError(let code, let msg):
                return String(localized: "Supabase erro \(code): \(msg)")
            }
        }
    }

    private let baseURL: URL?
    private let anonKey: String
    private static var temporarilyDisabledUntil: Date?
    private static let disableDuration: TimeInterval = 5 * 60

    /// `true` when both URL and anon key are present in `APIConfig`. When false,
    /// callers should silently skip Supabase (cache disabled) and proceed with
    /// the direct Exa/LLM path.
    var isConfigured: Bool {
        baseURL != nil && !anonKey.isEmpty && !Self.isTemporarilyDisabled
    }

    init() {
        let urlString = APIConfig.supabaseURL
        self.baseURL = urlString.isEmpty ? nil : URL(string: urlString)
        self.anonKey = APIConfig.supabaseAnonKey
    }

    // MARK: - Edge Functions

    func invokeFunctionData(
        name: String,
        body: [String: Any],
        acceptLanguage: String? = nil
    ) async throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await invokeFunctionData(
            name: name,
            body: data,
            contentType: "application/json",
            acceptLanguage: acceptLanguage
        )
    }

    func invokeFunctionData(
        name: String,
        body: Data,
        contentType: String,
        acceptLanguage: String? = nil
    ) async throws -> Data {
        guard let baseURL else { throw SupabaseError.notConfigured }
        let url = baseURL.appendingPathComponent("functions/v1/\(name)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyAuth(&request)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        if let acceptLanguage, !acceptLanguage.isEmpty {
            request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        }
        request.httpBody = body

        do {
            let (data, resp) = try await URLSession.shared.data(for: request)
            try validate(resp: resp, data: data)
            return data
        } catch {
            Self.noteFailureIfTransient(error)
            throw error
        }
    }

    // MARK: - Generic helpers

    /// PostgREST GET (`/rest/v1/<table>?...`).
    /// `query` is the raw query string (e.g. `"canonical_name=eq.ovo&locale=eq.pt-BR"`).
    func restGET<T: Decodable>(
        table: String,
        query: String,
        as type: T.Type
    ) async throws -> T {
        guard let baseURL else { throw SupabaseError.notConfigured }
        var components = URLComponents(url: baseURL.appendingPathComponent("/rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = query
        guard let url = components.url else { throw SupabaseError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(&request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, resp) = try await URLSession.shared.data(for: request)
            try validate(resp: resp, data: data)
            return try JSONDecoder.supabase.decode(T.self, from: data)
        } catch {
            Self.noteFailureIfTransient(error)
            throw error
        }
    }

    /// PostgREST RPC (`POST /rest/v1/rpc/<name>` with JSON body of named args).
    /// Discards the response body when `T == VoidResult.self`.
    @discardableResult
    func rpc<T: Decodable>(
        _ name: String,
        params: [String: Any],
        as type: T.Type = VoidResult.self
    ) async throws -> T {
        guard let baseURL else { throw SupabaseError.notConfigured }
        let url = baseURL.appendingPathComponent("/rest/v1/rpc/\(name)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyAuth(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: params)

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: request)
            try validate(resp: resp, data: data)
        } catch {
            Self.noteFailureIfTransient(error)
            throw error
        }

        if T.self == VoidResult.self {
            // Safe by construction: only reached when T == VoidResult.
            return unsafeBitCast(VoidResult(), to: T.self)
        }
        return try JSONDecoder.supabase.decode(T.self, from: data)
    }

    /// PostgREST insert (`POST /rest/v1/<table>` with a JSON body).
    func restPOST<Body: Encodable>(table: String, body: Body) async throws {
        guard let baseURL else { throw SupabaseError.notConfigured }
        let url = baseURL.appendingPathComponent("/rest/v1/\(table)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyAuth(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, resp) = try await URLSession.shared.data(for: request)
            try validate(resp: resp, data: data)
        } catch {
            Self.noteFailureIfTransient(error)
            throw error
        }
    }

    // MARK: - Internal

    private func applyAuth(_ request: inout URLRequest) {
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
    }

    private func validate(resp: URLResponse, data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseError.apiError(statusCode: http.statusCode, message: msg)
        }
    }

    private static var isTemporarilyDisabled: Bool {
        guard let until = temporarilyDisabledUntil else { return false }
        if until > Date() { return true }
        temporarilyDisabledUntil = nil
        return false
    }

    private static func noteFailureIfTransient(_ error: Error) {
        guard shouldTemporarilyDisable(for: error) else { return }
        temporarilyDisabledUntil = Date().addingTimeInterval(disableDuration)
        LLMLog.error("Supabase unavailable; skipping Supabase calls temporarily: \(error.localizedDescription)")
    }

    private static func shouldTemporarilyDisable(for error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .timedOut,
                 .dnsLookupFailed,
                 .secureConnectionFailed:
                return true
            default:
                return false
            }
        }

        if case SupabaseError.apiError(let statusCode, _) = error {
            return statusCode == 404 || statusCode == 429 || (500...599).contains(statusCode)
        }

        return false
    }
}

/// Sentinel for RPCs that don't return a meaningful body.
struct VoidResult: Decodable {}

extension JSONDecoder {
    /// Supabase returns ISO-8601 timestamps with fractional seconds; the date
    /// strategy here tolerates both `.iso8601` and the SQL form.
    static var supabase: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
