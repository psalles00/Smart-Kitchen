import Foundation
import XCTest
@testable import Savoria

@MainActor
final class AIServiceFallbackTests: XCTestCase {
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
