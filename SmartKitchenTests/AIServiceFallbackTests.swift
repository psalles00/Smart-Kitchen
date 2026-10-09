import Foundation
import XCTest
@testable import Savoria

@MainActor
final class AIServiceFallbackTests: XCTestCase {
    func testConfiguredBackendWinsOverAvailableDirectRouterKey() async throws {
        let backend = AvailableChatBackend()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DirectChatURLProtocol.self]
        var directCalls = 0
        DirectChatURLProtocol.requestHandler = { _ in
            directCalls += 1
            throw URLError(.badURL)
        }
        let service = AIService(supabase: backend,
                                urlSession: URLSession(configuration: configuration),
                                openRouterKey: { "unused-local-router-key" })
        let response = try await service.sendNutritionChat(
            messages: [["role": "user", "content": "arroz"]],
            tools: nil, apiKey: "", model: "gpt-4.1-mini", acceptLanguage: "pt-BR")
        XCTAssertFalse(APIConfig.usesLocalOpenRouter)
        XCTAssertEqual(response.content, "backend-ok")
        XCTAssertEqual(backend.calls, 1)
        XCTAssertEqual(directCalls, 0)
    }
    func testExplicitOpenRouterSkipsUnavailableBackendAndOpenAI() async throws {
        try await assertOpenRouterRouting(preferred: true)
    }

    func testBackendFailureFallsBackToOpenRouterWithNoOpenAIKey() async throws {
        try await assertOpenRouterRouting(preferred: false)
    }

    private func assertOpenRouterRouting(preferred: Bool) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DirectChatURLProtocol.self]
        var capturedRequest: URLRequest?
        var capturedBody: Data?
        DirectChatURLProtocol.requestHandler = { request in
            capturedRequest = request
            if let data = request.httpBody {
                capturedBody = data
            } else if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                var bytes = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    guard count > 0 else { break }
                    data.append(contentsOf: bytes.prefix(count))
                }
                capturedBody = data
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                    headerFields: ["Content-Type": "application/json"])!,
                    Data("{\"choices\":[{\"message\":{\"content\":\"ok\"}}]}".utf8))
        }
        let backend = CountingUnavailableBackend()
        let service = AIService(supabase: backend,
                                urlSession: URLSession(configuration: configuration),
                                openRouterKey: { "test-router-key" },
                                prefersDirectOpenRouter: { preferred })
        let response = try await service.sendNutritionChat(messages: [["role": "user", "content": "refeição de teste"]],
                                                           tools: nil, apiKey: "", model: "gpt-4.1-mini", acceptLanguage: "pt-BR")
        XCTAssertEqual(response.content, "ok")
        XCTAssertEqual(backend.calls, preferred ? 0 : 1)
        XCTAssertEqual(capturedRequest?.url?.host, "openrouter.ai")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-router-key")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(capturedBody)) as? [String: Any]
        XCTAssertEqual(body?["model"] as? String, OpenRouterModel.default)
    }
    override func tearDown() {
        super.tearDown()
        DirectChatURLProtocol.requestHandler = nil
    }

    func testChatFallsBackToDirectOpenAIWhenSupabaseHostCannotBeFound() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DirectChatURLProtocol.self]
        let session = URLSession(configuration: configuration)

        var capturedRequest: URLRequest?
        DirectChatURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = """
            {"choices":[{"message":{"content":"{\\"name\\":\\"Banana\\",\\"calories\\":105,\\"protein\\":1,\\"carbs\\":27,\\"fat\\":0,\\"serving_size_grams\\":118}"}}]}
            """.data(using: .utf8)!
            return (response, body)
        }

        let service = AIService(
            supabase: CannotFindHostSupabaseFunctionInvoker(),
            urlSession: session
        )

        let response = try await service.sendNutritionChat(
            messages: [["role": "user", "content": "banana"]],
            tools: nil,
            apiKey: "test-openai-key",
            model: "gpt-4.1-mini",
            acceptLanguage: "pt-BR"
        )

        XCTAssertEqual(response.content, "{\"name\":\"Banana\",\"calories\":105,\"protein\":1,\"carbs\":27,\"fat\":0,\"serving_size_grams\":118}")
        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-openai-key")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Accept-Language"), "pt-BR")
    }
}

@MainActor
private final class AvailableChatBackend: SupabaseFunctionInvoking {
    var isConfigured: Bool { true }
    private(set) var calls = 0
    func invokeFunctionData(name: String, body: [String: Any], acceptLanguage: String?) async throws -> Data {
        calls += 1
        return Data("{\"choices\":[{\"message\":{\"content\":\"backend-ok\"}}]}".utf8)
    }
    func invokeFunctionData(name: String, body: Data, contentType: String, acceptLanguage: String?) async throws -> Data {
        throw URLError(.unsupportedURL)
    }
}

@MainActor
private final class CountingUnavailableBackend: SupabaseFunctionInvoking {
    var isConfigured: Bool { true }
    private(set) var calls = 0
    func invokeFunctionData(name: String, body: [String: Any], acceptLanguage: String?) async throws -> Data {
        calls += 1
        throw URLError(.cannotFindHost)
    }
    func invokeFunctionData(name: String, body: Data, contentType: String, acceptLanguage: String?) async throws -> Data {
        calls += 1
        throw URLError(.cannotFindHost)
    }
}

@MainActor
private final class CannotFindHostSupabaseFunctionInvoker: SupabaseFunctionInvoking {
    var isConfigured: Bool { true }

    func invokeFunctionData(
        name: String,
        body: [String: Any],
        acceptLanguage: String?
    ) async throws -> Data {
        throw URLError(.cannotFindHost)
    }

    func invokeFunctionData(
        name: String,
        body: Data,
        contentType: String,
        acceptLanguage: String?
    ) async throws -> Data {
        throw URLError(.cannotFindHost)
    }
}

private final class DirectChatURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
