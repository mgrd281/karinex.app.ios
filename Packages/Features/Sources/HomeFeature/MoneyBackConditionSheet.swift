import DesignSystem
import SwiftUI

// MARK: - MoneyBackConditionSheet

/// The conditions of the "100 Tage Geld-zurück" promise, presented as a sheet from the trust
/// strip and from its footnote.
///
/// The clauses come from ``MoneyBackClause`` and state exactly the business rule of PROMPT.md
/// section 2: the promise applies only to activated license keys and physical goods, delivered
/// but not activated keys are not refunded voluntarily, and statutory warranty rights remain
/// untouched.
struct MoneyBackConditionSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.l) {
                    Text("home.moneyback.intro", bundle: .module)
                        .kxFont(.body)
                        .foregroundStyle(KXColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    KXCard {
                        VStack(alignment: .leading, spacing: KXSpacing.m) {
                            ForEach(MoneyBackClause.allCases) { clause in
                                MoneyBackClauseRow(clause: clause)
                                if clause != MoneyBackClause.allCases.last {
                                    KXDivider()
                                }
                            }
                        }
                    }
                }
                .padding(KXSpacing.gutter)
            }
            .accessibilityIdentifier("home.moneyback")
            .kxScreenBackground()
            .navigationTitle(Text("home.moneyback.title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("home.moneyback.done", bundle: .module)
                    }
                    .accessibilityIdentifier("home.moneyback.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Clause row

/// One condition: a decorative symbol and the clause text, read by VoiceOver as one element.
private struct MoneyBackClauseRow: View {
    let clause: MoneyBackClause

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: KXSpacing.s) {
            Image(systemName: clause.systemImage)
                .font(.system(.body, weight: .medium))
                .foregroundStyle(KXColor.brand)
                .accessibilityHidden(true)
            Text(clause.text)
                .kxFont(.body)
                .foregroundStyle(KXColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Money-back conditions, light") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            MoneyBackConditionSheet()
        }
}

#Preview("Money-back conditions, dark") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            MoneyBackConditionSheet()
        }
        .preferredColorScheme(.dark)
}

#Preview("Money-back conditions, accessibility size") {
    MoneyBackConditionSheet()
        .dynamicTypeSize(.accessibility2)
}
