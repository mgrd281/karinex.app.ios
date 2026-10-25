import DesignSystem
import SwiftUI
import Testing

extension DesignSystemSnapshotTests {
    /// `KXAccordion` with one row expanded (single expansion) and with custom row content.
    @MainActor
    @Suite("KXAccordion")
    struct KXAccordionSnapshotTests {
        @Test("Expanded and collapsed rows", arguments: SnapshotVariant.matrix)
        func variants(_ variant: SnapshotVariant) {
            let copy = SnapshotCopy.forLanguage(variant.language)
            let faq = [
                KXAccordionItem(title: copy.keyQuestion, text: copy.keyAnswer),
                KXAccordionItem(title: copy.paymentQuestion, text: copy.paymentAnswer),
                KXAccordionItem(title: copy.supportQuestion, text: copy.supportAnswer),
            ]
            let custom = [
                KXAccordionItem(title: copy.refundFact) {
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        Text(verbatim: copy.deliveryFact)
                        KXBadge(copy.digitalBadge, style: .neutral, systemImage: "envelope")
                    }
                },
            ]
            assertComponentSnapshot(variant: variant) {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    KXAccordion(items: faq, expansion: .single, initiallyExpanded: [copy.keyQuestion])
                    KXAccordion(items: custom, initiallyExpanded: [copy.refundFact])
                }
            }
        }
    }
}
