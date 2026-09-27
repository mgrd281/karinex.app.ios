@testable import Core
import Foundation
import Testing

@Suite("Locked")
struct LockedTests {
    @Test("Reads, mutates and replaces the value")
    func basicAccess() {
        let locked = Locked([1, 2])
        #expect(locked.value == [1, 2])
        let count = locked.withLock { values -> Int in
            values.append(3)
            return values.count
        }
        #expect(count == 3)
        #expect(locked.replace(with: [9]) == [1, 2, 3])
        #expect(locked.value == [9])
    }

    @Test("Releases the lock when the body throws")
    func releasesOnThrow() {
        let locked = Locked(0)
        #expect(throws: TestFailure.fatal) {
            try locked.withLock { value in
                value = 1
                throw TestFailure.fatal
            }
        }
        // The lock must be free again, otherwise this would deadlock.
        #expect(locked.withLock { $0 } == 1)
    }

    @Test("Serializes concurrent mutations")
    func concurrentIncrements() async {
        let counter = Locked(0)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    for _ in 0..<100 {
                        counter.withLock { $0 += 1 }
                    }
                }
            }
        }
        #expect(counter.value == 10_000)
    }
}
