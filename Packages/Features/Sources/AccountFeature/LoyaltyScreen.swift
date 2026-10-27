import BackendKit
import CommerceUI
import DesignSystem
import DesignTokens
#if canImport(PassKit) && canImport(UIKit)
import PassKit
#endif
import SwiftUI

// MARK: - LoyaltyFormat

/// Number, euro and date formatting of the loyalty screen, in the customer's locale.
struct LoyaltyFormat {
    let locale: Locale

    func points(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    func signedPoints(_ value: Int) -> String {
        value.formatted(.number.locale(locale).sign(strategy: .always()))
    }

    func euro(cents: Int) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: "EUR").locale(locale))
    }

    func date(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
    }
}

// MARK: - LoyaltyTier presentation

extension LoyaltyTier {
    /// The card colors of the level.
    var style: LoyaltyTierStyle {
        LoyaltyTierStyle(rawValue: rawValue) ?? .starter
    }

    /// The name of the level in the customer's language.
    var name: String {
        switch self {
        case .starter: String(localized: "account.loyalty.tier.starter", bundle: .module)
        case .silber: String(localized: "account.loyalty.tier.silber", bundle: .module)
        case .gold: String(localized: "account.loyalty.tier.gold", bundle: .module)
        case .platin: String(localized: "account.loyalty.tier.platin", bundle: .module)
        case .diamant: String(localized: "account.loyalty.tier.diamant", bundle: .module)
        case .elite: String(localized: "account.loyalty.tier.elite", bundle: .module)
        }
    }
}

// MARK: - LoyaltyScreen

/// "Treueprogramm": the membership card with the level ring, the reward points, the ways to
/// redeem them for a discount code and the history. Everything shown comes from the backend; the
/// app calculates nothing and keeps no balance.
public struct LoyaltyScreen: View {
    private let onApplyToCart: @MainActor (String) async -> Bool

    @State private var model: LoyaltyViewModel
    @State private var stepToConfirm: LoyaltyStatus.RedeemStep?
    @State private var isCollectSheetPresented = false
    @State private var cartNote: CartNote?
    #if canImport(PassKit) && canImport(UIKit)
    @State private var passToAdd: AddablePass?
    #endif

    @Environment(\.locale) private var locale

    private enum Anchor: Hashable {
        case rewards
        case history
    }

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - backend: The backend client.
    ///   - onApplyToCart: Adds a discount code to the cart and opens it; returns whether the
    ///     cart accepted the code.
    public init(backend: any BackendClient, onApplyToCart: @escaping @MainActor (String) async -> Bool) {
        _model = State(initialValue: LoyaltyViewModel(backend: backend))
        self.onApplyToCart = onApplyToCart
    }

    public var body: some View {
        AsyncContentView(
            model.state,
            retry: { await model.load() },
            content: { status in
                content(status)
            }
        )
        .accessibilityIdentifier("screen.loyalty")
        .kxScreenBackground()
        .navigationTitle(Text("account.loyalty.title", bundle: .module))
        .navigationBarTitleDisplayMode(.large)
        .task {
            if model.state.value == nil {
                await model.load()
            }
        }
        .sheet(isPresented: $isCollectSheetPresented) {
            if let status = model.state.value {
                LoyaltyCollectSheet(earn: status.earn, format: LoyaltyFormat(locale: locale))
            }
        }
        .sheet(item: codeBinding) { code in
            LoyaltyCodeSheet(code: code, format: LoyaltyFormat(locale: locale), note: cartNote) {
                cartNote = await onApplyToCart(code.code) ? .applied : .notApplied
            } onClose: {
                cartNote = nil
                model.dismissOutcome()
            }
        }
        .confirmationDialog(
            confirmTitle,
            isPresented: Binding(get: { stepToConfirm != nil }, set: { if !$0 { stepToConfirm = nil } }),
            titleVisibility: .visible,
            presenting: stepToConfirm
        ) { step in
            Button {
                Task { await model.redeem(step) }
            } label: {
                Text("account.loyalty.confirm.action", bundle: .module)
            }
        } message: { step in
            Text(conditions(for: step))
        }
        .alert(
            Text("account.loyalty.error.title", bundle: .module),
            isPresented: Binding(get: { failureMessage != nil }, set: { if !$0 { model.dismissOutcome() } })
        ) {
            Button(role: .cancel) {
                model.dismissOutcome()
            } label: {
                Text("account.signin.error.close", bundle: .module)
            }
        } message: {
            Text(failureMessage ?? "")
        }
        .alert(
            Text("account.loyalty.referral.error.title", bundle: .module),
            isPresented: $model.referralFailed
        ) {
            Button(role: .cancel) {} label: {
                Text("account.signin.error.close", bundle: .module)
            }
        } message: {
            Text("account.loyalty.referral.error.message", bundle: .module)
        }
        .alert(
            Text("account.loyalty.wallet.error.title", bundle: .module),
            isPresented: $model.walletPassFailed
        ) {
            Button(role: .cancel) {} label: {
                Text("account.signin.error.close", bundle: .module)
            }
        } message: {
            Text("account.loyalty.wallet.error.message", bundle: .module)
        }
        #if canImport(PassKit) && canImport(UIKit)
        .sheet(item: $passToAdd) { item in
            AddPassesSheet(pass: item.pass)
                .ignoresSafeArea()
        }
        #endif
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ status: LoyaltyStatus) -> some View {
        let format = LoyaltyFormat(locale: locale)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.xl) {
                    KXLoyaltyCard(
                        style: status.tier.tier.style,
                        tierName: status.tier.tier.name,
                        progress: status.tier.progress,
                        pointsLine: pointsLine(status.tier, format),
                        message: message(status.tier, format),
                        accessibilitySummary: summary(status.tier, format),
                        actions: [
                            KXLoyaltyCardAction(
                                id: "collect",
                                systemImage: "plus.circle",
                                title: String(localized: "account.loyalty.action.collect", bundle: .module)
                            ) {
                                isCollectSheetPresented = true
                            },
                            KXLoyaltyCardAction(
                                id: "rewards",
                                systemImage: "gift",
                                title: String(localized: "account.loyalty.action.rewards", bundle: .module)
                            ) {
                                withAnimation { proxy.scrollTo(Anchor.rewards, anchor: .top) }
                            },
                            KXLoyaltyCardAction(
                                id: "history",
                                systemImage: "clock.arrow.circlepath",
                                title: String(localized: "account.loyalty.action.history", bundle: .module)
                            ) {
                                withAnimation { proxy.scrollTo(Anchor.history, anchor: .top) }
                            },
                        ]
                    )
                    if !status.enabled {
                        Label {
                            Text("account.loyalty.disabled", bundle: .module)
                        } icon: {
                            Image(systemName: "pause.circle")
                                .accessibilityHidden(true)
                        }
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textSecondary)
                    }
                    walletCard
                    discount(status)
                    perks(status)
                    balance(status, format)
                    rewards(status, format)
                        .id(Anchor.rewards)
                    referral(status, format)
                    history(status, format)
                        .id(Anchor.history)
                }
                .padding(.horizontal, KXSpacing.gutter)
                .padding(.vertical, KXSpacing.m)
                .kxReadableWidth()
            }
            .refreshable { await model.load() }
        }
    }

    // MARK: Card texts

    private func pointsLine(_ level: LoyaltyStatus.Level, _ format: LoyaltyFormat) -> String {
        if let next = level.next {
            return String(
                localized: "account.loyalty.points.line.next \(format.points(level.points)) \(next.tier.name) \(format.points(next.min))",
                bundle: .module
            )
        }
        return String(localized: "account.loyalty.points.line.max \(format.points(level.points))", bundle: .module)
    }

    private func message(_ level: LoyaltyStatus.Level, _ format: LoyaltyFormat) -> String {
        if let next = level.next, !level.maxReached {
            return String(localized: "account.loyalty.message.next \(format.points(next.remaining)) \(next.tier.name)", bundle: .module)
        }
        return String(localized: "account.loyalty.message.max", bundle: .module)
    }

    private func summary(_ level: LoyaltyStatus.Level, _ format: LoyaltyFormat) -> String {
        if let next = level.next, !level.maxReached {
            return String(
                localized: "account.loyalty.summary \(level.tier.name) \(format.points(level.points)) \(format.points(next.min))",
                bundle: .module
            )
                + ". " + message(level, format)
        }
        return String(localized: "account.loyalty.summary.max \(level.tier.name) \(format.points(level.points))", bundle: .module)
    }

    // MARK: Sections

    /// "Zu Apple Wallet hinzufügen": the KARINEX customer card with level and points, only where
    /// the device can add passes.
    @ViewBuilder
    private var walletCard: some View {
        #if canImport(PassKit) && canImport(UIKit)
        if PKAddPassesViewController.canAddPasses() {
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                AddPassButton(isLoading: model.isLoadingWalletPass) {
                    Task { await addToWallet() }
                }
                .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
                .accessibilityIdentifier("loyalty.wallet")
                Text("account.loyalty.wallet.note", bundle: .module)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        #endif
    }

    #if canImport(PassKit) && canImport(UIKit)
    private func addToWallet() async {
        guard let data = await model.loadWalletPass() else { return }
        do {
            passToAdd = try AddablePass(pass: PKPass(data: data))
        } catch {
            model.walletPassFailed = true
        }
    }
    #endif

    /// "Freunde einladen": the friend saves on the first order with the customer's code, the
    /// customer gets reward points. The code is created on the first tap and shared with the
    /// system share sheet (message and the shop link that puts the code into the cart).
    @ViewBuilder
    private func referral(_ status: LoyaltyStatus, _ format: LoyaltyFormat) -> some View {
        if let referral = status.referral, referral.active {
            KXListGroup(Text("account.loyalty.referral.title", bundle: .module)) {
                VStack(alignment: .leading, spacing: KXSpacing.m) {
                    Text(
                        "account.loyalty.referral.body \(referral.friendPercent) \(format.points(referral.rewardPoints)) \(format.euro(cents: referral.rewardCents))",
                        bundle: .module
                    )
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    if let code = referral.code {
                        Text(verbatim: code)
                            .kxFont(.licenseKey)
                            .foregroundStyle(KXColor.keyCardText)
                            .frame(maxWidth: .infinity)
                            .padding(KXSpacing.m)
                            .background(KXColor.keyCardBackground, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
                            .textSelection(.enabled)
                            .accessibilityIdentifier("loyalty.referral.code")
                        if let link = referral.link {
                            ShareLink(
                                item: link,
                                subject: Text("account.loyalty.referral.share.subject", bundle: .module),
                                message: Text("account.loyalty.referral.share.message \(code) \(referral.friendPercent)", bundle: .module)
                            ) {
                                Label {
                                    Text("account.loyalty.referral.share", bundle: .module)
                                } icon: {
                                    Image(systemName: "square.and.arrow.up")
                                        .accessibilityHidden(true)
                                }
                            }
                            .buttonStyle(.kx(isFullWidth: true))
                            .accessibilityIdentifier("loyalty.referral.share")
                        }
                        KXButton(
                            String(localized: "account.loyalty.code.copy", bundle: .module),
                            systemImage: "doc.on.doc",
                            style: .secondary,
                            isFullWidth: true
                        ) {
                            KXClipboard.copySensitive(code)
                        }
                    } else {
                        KXButton(
                            String(localized: "account.loyalty.referral.create", bundle: .module),
                            systemImage: "person.badge.plus",
                            isFullWidth: true,
                            isLoading: model.isCreatingReferral
                        ) {
                            Task { await model.createReferral() }
                        }
                        .accessibilityIdentifier("loyalty.referral.create")
                    }
                    if referral.rewarded > 0 || referral.pending > 0 {
                        Text("account.loyalty.referral.count \(referral.rewarded) \(referral.pending)", bundle: .module)
                            .kxFont(.subheadline)
                            .foregroundStyle(KXColor.textSecondary)
                    }
                }
                .padding(KXSpacing.m)
            } footer: {
                Text("account.loyalty.referral.footer \(referral.maxPerYear)", bundle: .module)
            }
            .accessibilityIdentifier("loyalty.referral")
        }
    }

    /// "Ihr Dauerrabatt": the permanent discount of the level and the next one, only while the
    /// store has it switched on.
    @ViewBuilder
    private func discount(_ status: LoyaltyStatus) -> some View {
        if let discount = status.discount, discount.active {
            KXListGroup(Text("account.loyalty.discount.title", bundle: .module)) {
                if discount.percent > 0 {
                    KXListRow(
                        systemImage: "percent",
                        title: Text("account.loyalty.discount.current \(discount.percent)", bundle: .module),
                        detail: Text("account.loyalty.discount.current.detail", bundle: .module)
                    )
                } else {
                    KXListRow(systemImage: "percent", title: Text("account.loyalty.discount.none", bundle: .module))
                }
                if let next = discount.next {
                    KXListDivider()
                    KXListRow(
                        systemImage: "arrow.up.circle",
                        title: Text("account.loyalty.discount.next \(next.tier.name) \(next.percent)", bundle: .module)
                    )
                }
            } footer: {
                Text("account.loyalty.discount.footer \(status.earn.tierWindowMonths)", bundle: .module)
            }
            .accessibilityIdentifier("loyalty.discount")
        }
    }

    @ViewBuilder
    private func perks(_ status: LoyaltyStatus) -> some View {
        let code = locale.language.languageCode?.identifier ?? "de"
        let texts = status.perks.map { $0.text(languageCode: code) }.filter { !$0.isEmpty }
        if !texts.isEmpty {
            KXListGroup(Text("account.loyalty.perks.title", bundle: .module)) {
                ForEach(Array(texts.enumerated()), id: \.offset) { index, text in
                    if index > 0 {
                        KXListDivider()
                    }
                    KXListRow(systemImage: "sparkles", title: Text(verbatim: text))
                }
            }
        }
    }

    private func balance(_ status: LoyaltyStatus, _ format: LoyaltyFormat) -> some View {
        KXListGroup(Text("account.loyalty.balance.title", bundle: .module)) {
            KXListRow(
                systemImage: "gift",
                title: Text("account.loyalty.balance.available", bundle: .module),
                value: format.points(status.reward.available)
            )
            if status.reward.pending > 0 || status.tier.pending > 0 {
                KXListDivider()
                KXListRow(
                    systemImage: "hourglass",
                    title: Text("account.loyalty.balance.pending", bundle: .module),
                    detail: Text("account.loyalty.balance.pending.detail \(status.earn.holdDays)", bundle: .module),
                    value: format.points(status.reward.pending)
                )
            }
            if let expiring = status.reward.expiringSoon {
                KXListDivider()
                KXListRow(
                    systemImage: "exclamationmark.circle",
                    title: Text(
                        "account.loyalty.balance.expiring \(format.points(expiring.points)) \(format.date(expiring.at))",
                        bundle: .module
                    )
                )
            }
        } footer: {
            Text("account.loyalty.balance.footer", bundle: .module)
        }
        .accessibilityIdentifier("loyalty.balance")
    }

    private func rewards(_ status: LoyaltyStatus, _ format: LoyaltyFormat) -> some View {
        KXListGroup(Text("account.loyalty.rewards.title", bundle: .module)) {
            ForEach(Array(status.redeem.steps.enumerated()), id: \.element.id) { index, step in
                if index > 0 {
                    KXListDivider()
                }
                let enabled = model.canRedeem(step)
                Button {
                    stepToConfirm = step
                } label: {
                    ZStack(alignment: .trailing) {
                        KXListRow(
                            systemImage: "tag",
                            title: Text("account.loyalty.step.title \(format.euro(cents: step.cents))", bundle: .module),
                            detail: stepDetail(step, enabled: enabled, status: status, format: format),
                            accessory: model.redeeming == step.points ? .none : .chevron
                        )
                        if model.redeeming == step.points {
                            ProgressView()
                                .padding(.trailing, KXSpacing.m)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!enabled || model.redeeming != nil)
                .opacity(enabled ? 1 : 0.5)
                .accessibilityIdentifier("loyalty.step.\(step.points)")
            }
        } footer: {
            let redeem = status.redeem
            Text(
                "account.loyalty.rewards.footer \(redeem.maxPercent) \(format.euro(cents: redeem.minOrderCents)) \(redeem.codeValidDays)",
                bundle: .module
            )
        }
    }

    private func stepDetail(_ step: LoyaltyStatus.RedeemStep, enabled: Bool, status: LoyaltyStatus, format: LoyaltyFormat) -> Text {
        if enabled {
            return Text(
                "account.loyalty.step.detail \(format.points(step.points)) \(format.euro(cents: step.minSubtotalCents))",
                bundle: .module
            )
        }
        return Text("account.loyalty.step.missing \(format.points(max(0, step.points - status.reward.available)))", bundle: .module)
    }

    private func history(_ status: LoyaltyStatus, _ format: LoyaltyFormat) -> some View {
        KXListGroup(Text("account.loyalty.history.title", bundle: .module)) {
            if status.history.isEmpty {
                Text("account.loyalty.history.empty", bundle: .module)
                    .kxFont(.subheadline)
                    .foregroundStyle(KXColor.textSecondary)
                    .padding(KXSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(status.history.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        KXListDivider()
                    }
                    KXListRow(
                        systemImage: item.kind.systemImage,
                        title: Text(verbatim: historyTitle(item)),
                        detail: Text(verbatim: historyDetail(item, format)),
                        value: format.signedPoints(item.rewardPoints != 0 ? item.rewardPoints : item.statusPoints)
                    )
                }
            }
        }
        .accessibilityIdentifier("loyalty.history")
    }

    private func historyTitle(_ item: LoyaltyStatus.HistoryItem) -> String {
        if item.kind == .earn, item.isPending {
            return String(localized: "account.loyalty.history.earn.pending", bundle: .module)
        }
        return item.kind.title
    }

    private func historyDetail(_ item: LoyaltyStatus.HistoryItem, _ format: LoyaltyFormat) -> String {
        var parts = [format.date(item.date)]
        if let order = item.orderNumber, !order.isEmpty {
            parts.append(order)
        }
        // Which points moved, so a manual adjustment of one pool is not read as a change of the other.
        switch (item.statusPoints != 0, item.rewardPoints != 0) {
        case (true, true) where item.statusPoints == item.rewardPoints:
            parts.append(String(localized: "account.loyalty.history.pool.both", bundle: .module))
        case (true, true):
            parts.append(String(localized: "account.loyalty.history.pool.reward", bundle: .module))
            parts.append(String(localized: "account.loyalty.history.status \(format.signedPoints(item.statusPoints))", bundle: .module))
        case (true, false):
            parts.append(String(localized: "account.loyalty.history.pool.status", bundle: .module))
        case (false, true):
            parts.append(String(localized: "account.loyalty.history.pool.reward", bundle: .module))
        case (false, false):
            break
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Redeeming

    private var confirmTitle: Text {
        guard let step = stepToConfirm else { return Text(verbatim: "") }
        let format = LoyaltyFormat(locale: locale)
        return Text("account.loyalty.confirm.title \(format.euro(cents: step.cents)) \(format.points(step.points))", bundle: .module)
    }

    private func conditions(for step: LoyaltyStatus.RedeemStep) -> String {
        guard let status = model.state.value else { return "" }
        let format = LoyaltyFormat(locale: locale)
        let minimum = format.euro(cents: step.minSubtotalCents)
        return String(
            localized: "account.loyalty.confirm.message \(minimum) \(status.redeem.maxPercent) \(status.redeem.codeValidDays)",
            bundle: .module
        )
    }

    private var codeBinding: Binding<LoyaltyRedeemCode?> {
        Binding(
            get: {
                if case let .code(code) = model.outcome { return code }
                return nil
            },
            set: { if $0 == nil { model.dismissOutcome() } }
        )
    }

    private var failureMessage: String? {
        switch model.outcome {
        case .refused(.insufficient): String(localized: "account.loyalty.error.insufficient", bundle: .module)
        case .refused(.disabled): String(localized: "account.loyalty.error.disabled", bundle: .module)
        case .refused(.inProgress): String(localized: "account.loyalty.error.inprogress", bundle: .module)
        case .refused(.rejected): String(localized: "account.loyalty.error.rejected", bundle: .module)
        case .failed: String(localized: "account.loyalty.error.failed", bundle: .module)
        case .code, .none: nil
        }
    }
}

// MARK: - Code sheet

/// The note shown after "Im Warenkorb anwenden".
enum CartNote: Equatable {
    case applied
    case notApplied
}

/// The issued discount code: the code, what it is worth and when it ends, with "Kopieren" and
/// "Im Warenkorb anwenden".
private struct LoyaltyCodeSheet: View {
    let code: LoyaltyRedeemCode
    let format: LoyaltyFormat
    let note: CartNote?
    let onApply: @MainActor () async -> Void
    let onClose: @MainActor () -> Void

    @State private var isApplying = false
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.l) {
                    VStack(alignment: .leading, spacing: KXSpacing.xs) {
                        Text("account.loyalty.code.headline \(format.euro(cents: code.cents))", bundle: .module)
                            .kxFont(.title2)
                            .foregroundStyle(KXColor.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(
                            "account.loyalty.code.subtitle \(format.euro(cents: code.minSubtotalCents)) \(format.date(code.expiresAt))",
                            bundle: .module
                        )
                        .kxFont(.subheadline)
                        .foregroundStyle(KXColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(verbatim: code.code)
                        .kxFont(.licenseKey)
                        .foregroundStyle(KXColor.keyCardText)
                        .frame(maxWidth: .infinity)
                        .padding(KXSpacing.l)
                        .background(KXColor.keyCardBackground, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("loyalty.code")
                    KXButton(
                        String(localized: "account.loyalty.code.apply", bundle: .module),
                        systemImage: "cart",
                        isFullWidth: true,
                        isLoading: isApplying
                    ) {
                        Task {
                            isApplying = true
                            await onApply()
                            isApplying = false
                        }
                    }
                    KXButton(
                        didCopy
                            ? String(localized: "account.loyalty.code.copied", bundle: .module)
                            : String(localized: "account.loyalty.code.copy", bundle: .module),
                        systemImage: didCopy ? "checkmark" : "doc.on.doc",
                        style: .secondary,
                        isFullWidth: true
                    ) {
                        KXClipboard.copySensitive(code.code)
                        didCopy = true
                    }
                    if let note {
                        noteText(note)
                            .kxFont(.footnote)
                            .foregroundStyle(KXColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("account.loyalty.code.footer", bundle: .module)
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(KXSpacing.gutter)
                .kxReadableWidth()
            }
            .kxScreenBackground()
            .navigationTitle(Text("account.loyalty.code.title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onClose()
                    } label: {
                        Text("account.loyalty.code.done", bundle: .module)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func noteText(_ note: CartNote) -> Text {
        switch note {
        case .applied: Text("account.loyalty.code.note.applied", bundle: .module)
        case .notApplied: Text("account.loyalty.code.note.failed", bundle: .module)
        }
    }
}

// MARK: - Collect sheet

/// "Punkte sammeln": how points are earned, from the backend's rules.
private struct LoyaltyCollectSheet: View {
    let earn: LoyaltyStatus.Earn
    let format: LoyaltyFormat

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: KXSpacing.l) {
                    KXListGroup {
                        KXListRow(
                            systemImage: "cart",
                            title: Text(
                                "account.loyalty.collect.rate \(format.points(earn.tierPerEuro)) \(format.points(earn.rewardPerEuro))",
                                bundle: .module
                            ),
                            detail: Text("account.loyalty.collect.rate.detail", bundle: .module)
                        )
                        KXListDivider()
                        KXListRow(
                            systemImage: "hourglass",
                            title: Text("account.loyalty.collect.hold \(earn.holdDays)", bundle: .module),
                            detail: Text("account.loyalty.collect.hold.detail", bundle: .module)
                        )
                        KXListDivider()
                        KXListRow(
                            systemImage: "star",
                            title: Text("account.loyalty.collect.tier \(earn.tierWindowMonths)", bundle: .module),
                            detail: Text("account.loyalty.collect.tier.detail", bundle: .module)
                        )
                        KXListDivider()
                        KXListRow(
                            systemImage: "gift",
                            title: Text("account.loyalty.collect.reward \(earn.rewardExpiryMonths)", bundle: .module),
                            detail: Text("account.loyalty.collect.reward.detail", bundle: .module)
                        )
                    } footer: {
                        Text("account.loyalty.collect.footer", bundle: .module)
                    }
                }
                .padding(KXSpacing.gutter)
                .kxReadableWidth()
            }
            .kxScreenBackground()
            .navigationTitle(Text("account.loyalty.collect.title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("account.loyalty.code.done", bundle: .module)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - HistoryKind presentation

extension LoyaltyStatus.HistoryKind {
    fileprivate var systemImage: String {
        switch self {
        case .earn: "plus.circle"
        case .refund: "arrow.uturn.backward.circle"
        case .redeem: "tag"
        case .release: "arrow.counterclockwise.circle"
        case .adjust: "slider.horizontal.3"
        case .expire: "clock.badge.xmark"
        case .referral: "person.2"
        case .other: "circle"
        }
    }

    fileprivate var title: String {
        switch self {
        case .earn: String(localized: "account.loyalty.history.earn", bundle: .module)
        case .refund: String(localized: "account.loyalty.history.refund", bundle: .module)
        case .redeem: String(localized: "account.loyalty.history.redeem", bundle: .module)
        case .release: String(localized: "account.loyalty.history.release", bundle: .module)
        case .adjust: String(localized: "account.loyalty.history.adjust", bundle: .module)
        case .expire: String(localized: "account.loyalty.history.expire", bundle: .module)
        case .referral: String(localized: "account.loyalty.history.referral", bundle: .module)
        case .other: String(localized: "account.loyalty.history.other", bundle: .module)
        }
    }
}

// MARK: - Apple Wallet

#if canImport(PassKit) && canImport(UIKit)
/// A downloaded pass waiting for the add dialog.
private struct AddablePass: Identifiable {
    let id = UUID()
    let pass: PKPass
}

/// Apple's own "Add to Apple Wallet" button (artwork and wording come from the system, in the
/// customer's language), dimmed with a spinner while the card downloads.
private struct AddPassButton: UIViewRepresentable {
    let isLoading: Bool
    let action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.tag = Self.spinnerTag
        button.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
            spinner.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        return button
    }

    func updateUIView(_ button: PKAddPassButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = !isLoading
        button.alpha = isLoading ? 0.6 : 1
        if let spinner = button.viewWithTag(Self.spinnerTag) as? UIActivityIndicatorView {
            if isLoading {
                spinner.startAnimating()
            } else {
                spinner.stopAnimating()
            }
        }
    }

    private static let spinnerTag = 7_301

    @MainActor
    final class Coordinator: NSObject {
        var action: @MainActor () -> Void

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
        }

        @objc func tap() {
            action()
        }
    }
}

/// The system dialog that shows the card and adds it to Wallet. "Hinzufügen" and "Abbrechen"
/// both close it.
private struct AddPassesSheet: UIViewControllerRepresentable {
    let pass: PKPass
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: { dismiss() })
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard let controller = PKAddPassesViewController(pass: pass) else {
            return UIViewController()
        }
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}

    @MainActor
    final class Coordinator: NSObject, @preconcurrency PKAddPassesViewControllerDelegate {
        let dismiss: @MainActor () -> Void

        init(dismiss: @escaping @MainActor () -> Void) {
            self.dismiss = dismiss
        }

        func addPassesViewControllerDidFinish(_: PKAddPassesViewController) {
            dismiss()
        }
    }
}
#endif
