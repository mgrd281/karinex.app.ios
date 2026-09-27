@testable import Core
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing

@Suite("NetworkError")
struct NetworkErrorTests {
    @Test(
        "Maps connectivity codes to offline",
        arguments: [
            URLError.Code.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
            .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
        ]
    )
    func offline(code: URLError.Code) {
        let error = NetworkError(urlError: URLError(code))
        #expect(error == .offline)
        #expect(error.isConnectivityProblem)
    }

    @Test("Maps timeouts, cancellation and other codes")
    func otherCodes() {
        #expect(NetworkError(urlError: URLError(.timedOut)) == .timeout)
        #expect(NetworkError(urlError: URLError(.cancelled)) == .cancelled)
        #expect(
            NetworkError(urlError: URLError(.secureConnectionFailed))
                == .transport(code: URLError.Code.secureConnectionFailed.rawValue)
        )
        #expect(NetworkError(urlError: URLError(.badServerResponse)) == .transport(code: -1011))
        #expect(NetworkError(urlErrorCode: -1009) == .offline)
    }

    @Test("Only offline and timeout are connectivity problems")
    func connectivity() {
        #expect(NetworkError.timeout.isConnectivityProblem)
        #expect(!NetworkError.cancelled.isConnectivityProblem)
        #expect(!NetworkError.transport(code: -1200).isConnectivityProblem)
        #expect(!NetworkError.httpStatus(code: 503, retryAfter: 2).isConnectivityProblem)
        #expect(!NetworkError.invalidResponse.isConnectivityProblem)
    }

    @Test("URLSessionHTTPClient maps thrown errors to NetworkError")
    func clientErrorMapping() {
        #expect(URLSessionHTTPClient.networkError(for: URLError(.notConnectedToInternet)) == .offline)
        #expect(URLSessionHTTPClient.networkError(for: CancellationError()) == .cancelled)
        #expect(URLSessionHTTPClient.networkError(for: NetworkError.timeout) == .timeout)
        let nsError = NSError(domain: NSURLErrorDomain, code: URLError.Code.timedOut.rawValue)
        #expect(URLSessionHTTPClient.networkError(for: nsError) == .timeout)
        #expect(URLSessionHTTPClient.networkError(for: TestFailure.fatal) == .transport(code: URLError.Code.unknown.rawValue))
    }
}

@Suite("HTTP types")
struct HTTPTypesTests {
    private let url = URL(string: "https://45dv93-bk.myshopify.com/api/2026-07/graphql.json")!

    @Test("Request defaults and case-insensitive headers")
    func requestHeaders() {
        var request = HTTPRequest(url: url, headers: ["content-type": "text/plain"])
        #expect(request.method == .get)
        #expect(request.timeout == 30)
        #expect(request.body == nil)
        #expect(request.value(forHeader: "Content-Type") == "text/plain")

        request.setValue("application/json", forHeader: "Content-Type")
        #expect(request.headers == ["Content-Type": "application/json"])
        request.setValue(nil, forHeader: "CONTENT-TYPE")
        #expect(request.headers.isEmpty)
    }

    @Test("Methods use their HTTP spelling")
    func methods() {
        #expect(HTTPMethod.allCases.map(\.rawValue) == ["GET", "POST", "PUT", "PATCH", "DELETE"])
    }

    @Test("Converts to URLRequest")
    func urlRequestConversion() {
        let request = HTTPRequest(
            method: .post,
            url: url,
            headers: ["Content-Type": "application/json", "Accept": "application/json"],
            body: Data("{}".utf8),
            timeout: 12
        )
        let urlRequest = URLSessionHTTPClient.urlRequest(for: request)
        #expect(urlRequest.url == url)
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(urlRequest.httpBody == Data("{}".utf8))
        #expect(urlRequest.timeoutInterval == 12)
    }

    @Test("Response header lookup ignores case")
    func responseHeaders() {
        let response = HTTPResponse(statusCode: 200, headers: ["X-Request-Id": "abc", "content-type": "application/json"])
        #expect(response.value(forHeader: "x-request-id") == "abc")
        #expect(response.value(forHeader: "Content-Type") == "application/json")
        #expect(response.value(forHeader: "Retry-After") == nil)
        #expect(response.isSuccess)
        #expect(!HTTPResponse(statusCode: 304).isSuccess)
        #expect(HTTPResponse(statusCode: 204).body.isEmpty)
    }

    @Test("Parses Retry-After seconds", arguments: [("120", 120.0), (" 0 ", 0.0), ("1.5", 1.5)])
    func retryAfterSeconds(value: String, expected: TimeInterval) {
        let response = HTTPResponse(statusCode: 429, headers: ["retry-after": value])
        #expect(response.retryAfter(relativeTo: Date()) == expected)
        #expect(response.retryAfter == expected)
    }

    @Test(
        "Parses Retry-After HTTP-dates",
        arguments: [
            "Sun, 06 Nov 1994 08:49:37 GMT",
            "Sunday, 06-Nov-94 08:49:37 GMT",
            "Sun Nov  6 08:49:37 1994",
        ]
    )
    func retryAfterDates(value: String) throws {
        // 1994-11-06 08:49:37 UTC
        let reference = Date(timeIntervalSince1970: 784_111_777)
        let response = HTTPResponse(statusCode: 503, headers: ["Retry-After": value])
        let delay = try #require(response.retryAfter(relativeTo: reference.addingTimeInterval(-30)))
        #expect(abs(delay - 30) < 0.001)
        #expect(response.retryAfter(relativeTo: reference.addingTimeInterval(60)) == 0)
    }

    @Test("Rejects malformed Retry-After values", arguments: ["", "soon", "-5", "Sun, 32 Nov 1994 08:49:37 GMT", "inf"])
    func retryAfterMalformed(value: String) {
        let response = HTTPResponse(statusCode: 503, headers: ["Retry-After": value])
        #expect(response.retryAfter(relativeTo: Date()) == nil)
    }

    @Test("Default session configuration")
    func sessionConfiguration() {
        let configuration = URLSessionConfiguration.kxDefault
        #expect(configuration.timeoutIntervalForRequest == 30)
        #if !canImport(FoundationNetworking)
        #expect(!configuration.waitsForConnectivity)
        #endif
        #expect(configuration.urlCache?.memoryCapacity == 20 * 1024 * 1024)
        #expect(configuration.urlCache?.diskCapacity == 100 * 1024 * 1024)
        #expect(configuration.httpAdditionalHeaders == nil)
    }

    @Test("The client reports cancellation before sending")
    func cancelledBeforeSending() async {
        let client = URLSessionHTTPClient(configuration: .ephemeral)
        let url = url
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.send(HTTPRequest(url: url))
        }
        await #expect(throws: NetworkError.cancelled) {
            try await task.value
        }
    }
}
