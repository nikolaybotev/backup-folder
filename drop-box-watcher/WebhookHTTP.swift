import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct WebhookHTTPRequest: Sendable {
    let url: URL
    let authorization: String
    let body: Data
    let timeout: TimeInterval
}

struct WebhookHTTPResponse: Sendable {
    let statusCode: Int
}

protocol WebhookTransport: Sendable {
    func post(_ request: WebhookHTTPRequest) async throws -> WebhookHTTPResponse
}

/// Production transport; only type that uses `URLSession` (FR11).
final class URLSessionWebhookTransport: WebhookTransport, @unchecked Sendable {
    func post(_ request: WebhookHTTPRequest) async throws -> WebhookHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(request.authorization, forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        _ = data
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return WebhookHTTPResponse(statusCode: http.statusCode)
    }
}

protocol WebhookSleeper: Sendable {
    func sleep(seconds: Double) async throws
}

struct RealWebhookSleeper: WebhookSleeper {
    func sleep(seconds: Double) async throws {
        let ns = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: ns)
    }
}
