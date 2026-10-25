import DesignSystem
import Foundation
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// `KXCountdown` rendered as static frames for a fixed reference date: with days, below
    /// 24 hours and ended, in both tile styles and sizes. Nothing depends on the current time.
    @MainActor
    @Suite("KXCountdown")
    struct KXCountdownSnapshotTests {
        /// 2026-09-26, the day the store samples were recorded.
        private static let referenceDate = Date(timeIntervalSinceReferenceDate: 812_160_000)

        @Test("Days, hours and ended", arguments: SnapshotVariant.matrix)
        func variants(_ variant: SnapshotVariant) {
            let reference = Self.referenceDate
            assertComponentSnapshot(variant: variant) {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    KXCountdown(endsAt: reference.addingTimeInterval(2 * 86_400 + 3 * 3_600 + 4 * 60 + 5), now: reference)
                    KXCountdown(
                        endsAt: reference.addingTimeInterval(3 * 3_600 + 4 * 60 + 5),
                        now: reference,
                        style: .brand,
                        size: .compact
                    )
                    KXCountdown(endsAt: reference, now: reference, size: .compact)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
