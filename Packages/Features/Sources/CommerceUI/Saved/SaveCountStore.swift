import Core
import Foundation
import Observation

// MARK: - SaveCountStore

/// How many customers saved a product with the heart, the same number the web shop shows beside
/// its heart.
///
/// - The web shop keeps one counter per product handle; the KARINEX backend reads and updates it
///   (`GET`/`POST /v1/app/save-counts`), so the app never talks to the counter's host itself and
///   no customer data leaves the device: a request carries only the product handle.
/// - The number is shown from ``minimumCount`` on and never invented: offline, without a backend
///   or on any failure the store has no number and the screen shows none.
@MainActor
@Observable
public final class SaveCountStore {
    /// The smallest number the screens show.
    public static let minimumCount = 1

    /// The last known counts by product handle.
    public private(set) var counts: [String: Int] = [:]

    @ObservationIgnored private let http: any HTTPClient
    @ObservationIgnored private let endpoint: URL?

    /// Creates the store.
    ///
    /// - Parameters:
    ///   - http: The transport.
    ///   - backendBaseURL: `AppConfiguration.backendBaseURL`; `nil` shows no counts.
    public init(http: any HTTPClient, backendBaseURL: URL?) {
        self.http = http
        endpoint = backendBaseURL?.appendingPathComponent("v1/app/save-counts")
    }

    /// The number to show beside the heart, or `nil` to show none.
    public func displayCount(for handle: String) -> Int? {
        guard let count = counts[handle], count >= Self.minimumCount else { return nil }
        return count
    }

    /// Reads the counter of `handle`.
    public func refresh(handle: String) async {
        guard let endpoint, var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
        components.queryItems = [URLQueryItem(name: "handle", value: handle)]
        guard let url = components.url, let count = await send(HTTPRequest(url: url, timeout: 10)) else { return }
        counts[handle] = count
    }

    /// Counts a save (`isSaved`) or its removal. The number moves at once and then takes the
    /// value the backend reports.
    public func didChange(handle: String, isSaved: Bool) async {
        guard let endpoint else { return }
        let known = counts[handle] ?? 0
        counts[handle] = isSaved ? known + 1 : max(0, known - 1)
        guard let body = try? JSONEncoder().encode(Change(handle: handle, saved: isSaved)) else { return }
        let request = HTTPRequest(
            method: .post,
            url: endpoint,
            headers: ["Content-Type": "application/json"],
            body: body,
            timeout: 10
        )
        if let count = await send(request) {
            counts[handle] = count
        }
    }

    private func send(_ request: HTTPRequest) async -> Int? {
        guard let response = try? await http.send(request), response.isSuccess else { return nil }
        return (try? JSONDecoder().decode(Counter.self, from: response.body))?.count
    }

    private struct Counter: Decodable {
        let count: Int
    }

    private struct Change: Encodable {
        let handle: String
        let saved: Bool
    }
}
