import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// `KXStepTimeline` as an informational process ("So läuft es ab") and as a progress timeline
    /// with done, current and upcoming steps, in both directions.
    @MainActor
    @Suite("KXStepTimeline")
    struct KXStepTimelineSnapshotTests {
        @Test("Process explanation", arguments: SnapshotVariant.matrix)
        func process(_ variant: SnapshotVariant) {
            let copy = SnapshotCopy.forLanguage(variant.language)
            let steps = [
                KXStepTimeline.Step(title: copy.orderStep, detail: copy.orderStepDetail),
                KXStepTimeline.Step(title: copy.payStep, detail: copy.payStepDetail),
                KXStepTimeline.Step(title: copy.keyStep, detail: copy.keyStepDetail),
            ]
            assertComponentSnapshot(variant: variant) {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    KXStepTimeline(steps: steps, direction: .horizontal)
                    KXStepTimeline(steps: steps)
                }
            }
        }

        @Test("Progress states", arguments: SnapshotVariant.matrix)
        func progress(_ variant: SnapshotVariant) {
            let copy = SnapshotCopy.forLanguage(variant.language)
            let steps = [
                KXStepTimeline.Step(title: copy.orderedState, state: .done),
                KXStepTimeline.Step(title: copy.paidState, detail: copy.payStepDetail, state: .current),
                KXStepTimeline.Step(title: copy.licenseSentState, state: .upcoming),
            ]
            assertComponentSnapshot(variant: variant) {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    KXStepTimeline(steps: steps)
                    KXStepTimeline(steps: steps, direction: .horizontal)
                }
            }
        }
    }
}
