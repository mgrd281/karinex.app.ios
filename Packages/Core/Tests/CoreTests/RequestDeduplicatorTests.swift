@testable import Core
import Foundation
import Testing

@Suite("RequestDeduplicator")
struct RequestDeduplicatorTests {
    @Test("Concurrent calls with the same key share one execution")
    func concurrentCallsShareExecution() async throws {
        let deduplicator = RequestDeduplicator<String, Int>()
        let executions = Locked(0)
        let gate = Gate()
        let callers = 10

        let results = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<callers {
                group.addTask {
                    try await deduplicator.value(for: "product") {
                        executions.withLock { $0 += 1 }
                        await gate.wait()
                        return 42
                    }
                }
            }
            let allJoined = await eventually { await deduplicator.waiterCount(for: "product") == callers }
            #expect(allJoined)
            await gate.open()
            return try await group.reduce(into: [Int]()) { $0.append($1) }
        }

        #expect(results == Array(repeating: 42, count: callers))
        #expect(executions.value == 1)
        #expect(await deduplicator.inFlightCount == 0)
    }

    @Test("Sequential calls execute twice")
    func sequentialCallsExecuteAgain() async throws {
        let deduplicator = RequestDeduplicator<String, Int>()
        let executions = Locked(0)
        let operation: @Sendable () async throws -> Int = {
            executions.withLock { count -> Int in
                count += 1
                return count
            }
        }
        let first = try await deduplicator.value(for: "key", operation: operation)
        let second = try await deduplicator.value(for: "key", operation: operation)
        #expect(first == 1)
        #expect(second == 2)
        #expect(executions.value == 2)
    }

    @Test("Different keys execute independently")
    func differentKeys() async throws {
        let deduplicator = RequestDeduplicator<Int, Int>()
        let executions = Locked(0)
        async let first = deduplicator.value(for: 1) {
            executions.withLock { $0 += 1 }
            return 1
        }
        async let second = deduplicator.value(for: 2) {
            executions.withLock { $0 += 1 }
            return 2
        }
        let values = try await [first, second]
        #expect(values == [1, 2])
        #expect(executions.value == 2)
    }

    @Test("Failures are shared and not cached")
    func failuresAreSharedAndCleared() async throws {
        let deduplicator = RequestDeduplicator<String, Int>()
        let executions = Locked(0)
        await #expect(throws: TestFailure.fatal) {
            try await deduplicator.value(for: "key") {
                executions.withLock { $0 += 1 }
                throw TestFailure.fatal
            }
        }
        #expect(await deduplicator.inFlightCount == 0)
        let value = try await deduplicator.value(for: "key") {
            executions.withLock { $0 += 1 }
            return 7
        }
        #expect(value == 7)
        #expect(executions.value == 2)
    }

    @Test("Cancelling the only caller cancels the shared operation")
    func lastCallerCancellationCancelsOperation() async {
        let deduplicator = RequestDeduplicator<String, Int>()
        let operationSawCancellation = Locked(false)
        let task = Task {
            try await deduplicator.value(for: "slow") {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    operationSawCancellation.withLock { $0 = true }
                    throw error
                }
                return 1
            }
        }
        let joined = await eventually { await deduplicator.waiterCount(for: "slow") == 1 }
        #expect(joined)
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(operationSawCancellation.value)
        let cleared = await eventually { await deduplicator.inFlightCount == 0 }
        #expect(cleared)
    }

    @Test("Cancelling one of several callers keeps the operation running for the others")
    func partialCancellationKeepsOperation() async throws {
        let deduplicator = RequestDeduplicator<String, Int>()
        let gate = Gate()
        let executions = Locked(0)
        let operation: @Sendable () async throws -> Int = {
            executions.withLock { $0 += 1 }
            await gate.wait()
            return 5
        }

        let cancelled = Task { try await deduplicator.value(for: "shared", operation: operation) }
        let kept = Task { try await deduplicator.value(for: "shared", operation: operation) }
        let bothJoined = await eventually { await deduplicator.waiterCount(for: "shared") == 2 }
        #expect(bothJoined)

        cancelled.cancel()
        let oneLeft = await eventually { await deduplicator.waiterCount(for: "shared") == 1 }
        #expect(oneLeft)
        await gate.open()

        #expect(try await kept.value == 5)
        #expect(try await cancelled.value == 5)
        #expect(executions.value == 1)
    }
}
