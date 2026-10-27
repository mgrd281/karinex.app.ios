import Core
import Foundation
import Observation

// MARK: - SaveCountStore

/// How many customers saved a product with the heart, the same number the web shop shows beside
/// its heart.
///
/// - The web shop keeps one counter per product handle in its Firebase Realtime Database
///   (`wishlist/<handle>.json`, `{"count": n}`); the app reads and writes the same counters.
/// - Nothing is read or written until the customer allowed anonymous usage analytics, as in the
///   web shop; a counter request carries only the product handle, no customer data.
/// - The number is shown from ``minimumCount`` on and never invented: without consent, offline or on
///   any failure the store has no number and the screen shows none.
@MainActor
@Observable
public final class SaveCountStore {
    /// The base address of the counters.
    public static let baseURL = URL(string: "https://karinex-final-default-rtdb.europe-west1.firebasedatabase.app/wishlist")!
    /// The smallest number the screens show.
    public static let minimumCount = 1

    /// The last known counts by product handle.
    public private(set) var counts: [String: Int] = [:]

    @ObservationIgnored private let http: any HTTPClient
    @ObservationIgnored private let consentStore: any ConsentStoring

    /// Creates the store.
    public init(http: any HTTPClient, consentStore: any ConsentStoring) {
        self.http = http
        self.consentStore = consentStore
    }

    /// The number to show beside the heart, or `nil` to show none.
    public func displayCount(for handle: String) -> Int? {
        guard let count = counts[handle], count >= Self.minimumCount else { return nil }
        return count
    }

    /// Reads the counter of `handle`.
    public func refresh(handle: String) async {
        guard consentStore.load().analytics, let count = await read(handle) else { return }
        counts[handle] = count
    }

    /// Counts a save (`isSaved`) or its removal. The number moves at once and the counter is
    /// written after reading its current value, like the web shop.
    public func didChange(handle: String, isSaved: Bool) async {
        guard consentStore.load().analytics else { return }
        let known = counts[handle] ?? 0
        counts[handle] = isSaved ? known + 1 : max(0, known - 1)
        guard let current = await read(handle) else { return }
        let next = isSaved ? current + 1 : max(0, current - 1)
        if await write(next, handle: handle) {
            counts[handle] = next
        }
    }

    // MARK: Firebase

    private func url(_ handle: String) -> URL {
        Self.baseURL.appendingPathComponent("\(handle).json")
    }

    private func read(_ handle: String) async -> Int? {
        do {
            let response = try await http.send(HTTPRequest(url: url(handle), timeout: 10))
            guard response.isSuccess else { return nil }
            if response.body.isEmpty || String(decoding: response.body, as: UTF8.self) == "null" {
                return 0
            }
            return try JSONDecoder().decode(Counter.self, from: response.body).count
        } catch {
            return nil
        }
    }

    private func write(_ count: Int, handle: String) async -> Bool {
        guard let body = try? JSONEncoder().encode(Counter(count: count)) else { return false }
        let request = HTTPRequest(
            method: .put,
            url: url(handle),
            headers: ["Content-Type": "application/json"],
            body: body,
            timeout: 10
        )
        return await (try? http.send(request))?.isSuccess == true
    }

    private struct Counter: Codable {
        let count: Int
    }
}
