@testable import Core
import Foundation
import Testing

@Suite("Network monitoring")
struct NetworkMonitorTests {
    private static let wifi = NetworkStatus.online(isExpensive: false, isConstrained: false)
    private static let cellular = NetworkStatus.online(isExpensive: true, isConstrained: false)

    @Test("Status helpers")
    func statusHelpers() {
        #expect(Self.wifi.isOnline)
        #expect(!NetworkStatus.offline.isOnline)
        #expect(!Self.wifi.prefersReducedDataUsage)
        #expect(Self.cellular.prefersReducedDataUsage)
        #expect(NetworkStatus.online(isExpensive: false, isConstrained: true).prefersReducedDataUsage)
    }

    @Test("Static monitor reports its status once")
    func staticMonitor() async {
        let monitor = StaticNetworkMonitor(status: .offline)
        #expect(await monitor.currentStatus == .offline)
        var received: [NetworkStatus] = []
        for await status in monitor.statusUpdates() {
            received.append(status)
        }
        #expect(received == [.offline])
        #expect(await StaticNetworkMonitor().currentStatus == Self.wifi)
    }

    @Test("Manual monitor delivers the current status and later changes")
    func manualMonitorUpdates() async {
        let monitor = ManualNetworkMonitor(initialStatus: Self.wifi)
        var iterator = monitor.statusUpdates().makeAsyncIterator()
        #expect(await iterator.next() == Self.wifi)

        monitor.update(to: .offline)
        #expect(await iterator.next() == .offline)
        #expect(await monitor.currentStatus == .offline)

        monitor.update(to: .offline)
        monitor.update(to: Self.cellular)
        #expect(await iterator.next() == Self.cellular)
    }

    @Test("Every subscriber gets its own stream")
    func multipleSubscribers() async {
        let monitor = ManualNetworkMonitor()
        var first = monitor.statusUpdates().makeAsyncIterator()
        var second = monitor.statusUpdates().makeAsyncIterator()
        #expect(await first.next() == Self.wifi)
        #expect(await second.next() == Self.wifi)
        monitor.update(to: .offline)
        #expect(await first.next() == .offline)
        #expect(await second.next() == .offline)
    }

    @Test("Streams finish when the monitor is released")
    func finishesOnDeinit() async {
        var monitor: ManualNetworkMonitor? = ManualNetworkMonitor()
        let stream = monitor?.statusUpdates()
        var iterator = stream?.makeAsyncIterator()
        #expect(await iterator?.next() == Self.wifi)
        monitor = nil
        #expect(await iterator?.next() == nil)
    }

    @Test("Readers wait for the first status")
    func waitsForFirstStatus() async {
        let broadcaster = NetworkStatusBroadcaster(initialStatus: nil)
        let reader = Task { await broadcaster.currentStatus() }
        var iterator = broadcaster.makeStream().makeAsyncIterator()
        broadcaster.publish(.offline)
        #expect(await reader.value == .offline)
        #expect(await iterator.next() == .offline)
        broadcaster.finishAll()
        #expect(await iterator.next() == nil)
    }

    @Test("Cancelled subscribers are removed")
    func cancelledSubscriberIsRemoved() async {
        let broadcaster = NetworkStatusBroadcaster(initialStatus: .offline)
        let consumer = Task {
            for await _ in broadcaster.makeStream() {}
        }
        let subscribed = await eventually { broadcaster.subscriberCount == 1 }
        #expect(subscribed)
        consumer.cancel()
        await consumer.value
        let removed = await eventually { broadcaster.subscriberCount == 0 }
        #expect(removed)
        broadcaster.publish(Self.wifi)
    }
}
