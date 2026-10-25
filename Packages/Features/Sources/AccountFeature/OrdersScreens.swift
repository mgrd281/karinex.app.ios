import BackendKit
import CommerceUI
import DesignSystem
import Foundation
import Observation
import ShopifyKit
import SwiftUI

// MARK: - OrdersViewModel

/// The customer's orders, newest first, with cursor pagination and the backend's delivery
/// state when the backend is available.
@MainActor
@Observable
final class OrdersViewModel {
    /// Orders per page.
    static let pageSize = 20

    /// The load state of the first page.
    private(set) var state: LoadState<[CustomerOrder]> = .idle
    /// Whether the next page is loading.
    private(set) var isLoadingMore = false
    /// The delivery state per numeric order ID.
    private(set) var deliveries: [String: DeliveryStatus] = [:]

    @ObservationIgnored private let repository: any CustomerAccountRepository
    @ObservationIgnored private let backend: any BackendClient
    @ObservationIgnored private var nextCursor: String?

    init(repository: any CustomerAccountRepository, backend: any BackendClient) {
        self.repository = repository
        self.backend = backend
    }

    /// Loads the first page and the delivery states.
    func load() async {
        if state.value == nil {
            state = .loading
        }
        async let deliveryStates = loadDeliveries()
        do {
            let page = try await repository.orders(first: Self.pageSize, after: nil)
            nextCursor = page.nextCursor
            state = LoadState(page.orders, isEmpty: \.isEmpty)
        } catch {
            if let failure = UserFacingError(error), state.value == nil {
                state = .failed(failure)
            }
        }
        if let loaded = await deliveryStates {
            deliveries = loaded
        }
    }

    /// Loads the next page when `order` is one of the last three shown.
    func loadMoreIfNeeded(after order: CustomerOrder) async {
        guard let orders = state.value, let cursor = nextCursor, !isLoadingMore,
              let index = orders.firstIndex(of: order), index >= orders.count - 3
        else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await repository.orders(first: Self.pageSize, after: cursor)
            nextCursor = page.nextCursor
            let known = Set(orders.map(\.id))
            state = .loaded(orders + page.orders.filter { !known.contains($0.id) })
        } catch {
            nextCursor = cursor
        }
    }

    /// The delivery state of `order`, if the backend reported one.
    func delivery(for order: CustomerOrder) -> DeliveryStatus? {
        order.numericID.flatMap { deliveries[$0] }
    }

    private func loadDeliveries() async -> [String: DeliveryStatus]? {
        guard let orders = try? await backend.orders() else { return nil }
        return Dictionary(orders.map { ($0.orderID, $0.deliveryStatus) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - OrdersScreen

/// "Bestellungen": every order with number, date, total and a status pill.
public struct OrdersScreen: View {
    private let onRoute: @MainActor (CommerceRoute) -> Void

    @State private var model: OrdersViewModel

    @Environment(\.locale) private var locale

    /// Creates the list.
    public init(
        repository: any CustomerAccountRepository,
        backend: any BackendClient,
        onRoute: @escaping @MainActor (CommerceRoute) -> Void
    ) {
        _model = State(initialValue: OrdersViewModel(repository: repository, backend: backend))
        self.onRoute = onRoute
    }

    public var body: some View {
        AsyncContentView(
            model.state,
            empty: AsyncContentEmptyState(
                systemImage: "shippingbox",
                title: String(localized: "account.orders.empty.title", bundle: .module),
                message: String(localized: "account.orders.empty.message", bundle: .module)
            ),
            retry: { await model.load() },
            content: { orders in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: KXSpacing.m) {
                        ForEach(orders) { order in
                            Button {
                                onRoute(.account(.order(id: order.id)))
                            } label: {
                                OrderRow(
                                    order: order,
                                    pill: OrderStatusPill(order: order, delivery: model.delivery(for: order)),
                                    locale: locale
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("account.order.\(order.numericID ?? order.name)")
                            .task {
                                await model.loadMoreIfNeeded(after: order)
                            }
                        }
                        if model.isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, KXSpacing.m)
                        }
                    }
                    .padding(.horizontal, KXSpacing.gutter)
                    .padding(.vertical, KXSpacing.m)
                }
                .refreshable { await model.load() }
            },
            placeholder: {
                AsyncContentSkeleton()
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.orders")
        .kxScreenBackground()
        .navigationTitle(Text("account.orders.title", bundle: .module))
        .navigationBarTitleDisplayMode(.large)
        .task {
            if model.state.value == nil {
                await model.load()
            }
        }
    }
}

/// One order in the list.
private struct OrderRow: View {
    let order: CustomerOrder
    let pill: OrderStatusPill
    let locale: Locale

    var body: some View {
        KXCard {
            HStack(alignment: .top, spacing: KXSpacing.m) {
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Text(order.name)
                        .kxFont(.headline)
                        .foregroundStyle(KXColor.textPrimary)
                    Text(order.processedAt.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(locale)))
                        .kxFont(.subheadline)
                        .foregroundStyle(KXColor.textSecondary)
                    Text(order.totalPrice.formatted(locale: locale))
                        .kxFont(.body)
                        .foregroundStyle(KXColor.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                KXBadge(pill.title, style: pill.style)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - OrderDetailViewModel

/// One order with its timeline, lines and totals, and the invoice link from the backend.
@MainActor
@Observable
final class OrderDetailViewModel {
    /// What the invoice button shows.
    enum InvoiceState: Equatable {
        case idle
        case loading
        /// The invoice comes by e-mail only (no backend yet).
        case byEmail
        case failed(UserFacingError)
    }

    /// The order GID.
    let orderID: ShopifyID
    /// The load state.
    private(set) var state: LoadState<CustomerOrder> = .idle
    /// The backend's delivery state, if known.
    private(set) var delivery: DeliveryStatus?
    /// The invoice button state.
    private(set) var invoiceState: InvoiceState = .idle

    @ObservationIgnored private let repository: any CustomerAccountRepository
    @ObservationIgnored private let backend: any BackendClient

    init(orderID: ShopifyID, repository: any CustomerAccountRepository, backend: any BackendClient) {
        self.orderID = orderID
        self.repository = repository
        self.backend = backend
    }

    /// Loads the order and its delivery state.
    func load() async {
        if state.value == nil {
            state = .loading
        }
        do {
            let order = try await repository.order(id: orderID)
            state = LoadState(order)
            if let numericID = order?.numericID, let orders = try? await backend.orders() {
                delivery = orders.first { $0.orderID == numericID }?.deliveryStatus
            }
        } catch {
            if let failure = UserFacingError(error), state.value == nil {
                state = .failed(failure)
            }
        }
    }

    /// Requests a short-lived invoice link; `nil` when there is none to open.
    func invoiceURL() async -> URL? {
        guard let numericID = state.value?.numericID else { return nil }
        invoiceState = .loading
        do {
            let link = try await backend.invoice(orderID: numericID)
            invoiceState = .idle
            return link.url
        } catch BackendError.notConfigured {
            invoiceState = .byEmail
        } catch BackendError.notFound {
            invoiceState = .byEmail
        } catch {
            invoiceState = UserFacingError(error).map(InvoiceState.failed) ?? .idle
        }
        return nil
    }
}

// MARK: - OrderDetailScreen

/// An order: number and date, the vertical timeline, the lines, the totals exactly as Shopify
/// returns them, "Rechnung (PDF)", "Lizenzschlüssel anzeigen" and help with this order.
public struct OrderDetailScreen: View {
    private let onRoute: @MainActor (CommerceRoute) -> Void

    @State private var model: OrderDetailViewModel

    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    /// Creates the screen.
    public init(
        orderID: ShopifyID,
        repository: any CustomerAccountRepository,
        backend: any BackendClient,
        onRoute: @escaping @MainActor (CommerceRoute) -> Void
    ) {
        _model = State(initialValue: OrderDetailViewModel(orderID: orderID, repository: repository, backend: backend))
        self.onRoute = onRoute
    }

    public var body: some View {
        AsyncContentView(
            model.state,
            empty: AsyncContentEmptyState(
                systemImage: "doc.text.magnifyingglass",
                title: String(localized: "account.order.empty.title", bundle: .module),
                message: String(localized: "account.order.empty.message", bundle: .module)
            ),
            retry: { await model.load() },
            content: { order in
                ScrollView {
                    content(order)
                }
                .refreshable { await model.load() }
            },
            placeholder: {
                AsyncContentSkeleton()
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.order")
        .kxScreenBackground()
        .navigationTitle(model.state.value?.name ?? String(localized: "account.order.title", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model.state.value == nil {
                await model.load()
            }
        }
    }

    private func content(_ order: CustomerOrder) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.xl) {
            header(order)
            KXCard {
                KXStepTimeline(steps: OrderTimeline.steps(for: order, delivery: model.delivery, locale: locale))
            }
            .accessibilityIdentifier("account.order.timeline")
            if !order.lineItems.isEmpty {
                lines(order)
            }
            totals(order)
            actions(order)
        }
        .padding(.horizontal, KXSpacing.gutter)
        .padding(.vertical, KXSpacing.m)
    }

    private func header(_ order: CustomerOrder) -> some View {
        let pill = OrderStatusPill(order: order, delivery: model.delivery)
        return VStack(alignment: .leading, spacing: KXSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(order.name)
                    .kxFont(.title1)
                    .foregroundStyle(KXColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: KXSpacing.s)
                KXBadge(pill.title, style: pill.style)
            }
            if let confirmation = order.confirmationNumber {
                Text("account.order.confirmation \(confirmation)", bundle: .module)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
            }
        }
    }

    private func lines(_ order: CustomerOrder) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSectionHeader(String(localized: "account.order.lines", bundle: .module))
            KXCard {
                VStack(alignment: .leading, spacing: KXSpacing.m) {
                    ForEach(order.lineItems) { line in
                        OrderLineRow(line: line, locale: locale)
                        if line.id != order.lineItems.last?.id {
                            KXDivider()
                        }
                    }
                }
            }
        }
    }

    private func totals(_ order: CustomerOrder) -> some View {
        KXCard {
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                if let subtotal = order.subtotal {
                    KXSpecRow(String(localized: "account.order.subtotal", bundle: .module), value: subtotal.formatted(locale: locale))
                }
                if let shipping = order.totalShipping, !shipping.isZero {
                    KXSpecRow(String(localized: "account.order.shipping", bundle: .module), value: shipping.formatted(locale: locale))
                }
                if let tax = order.totalTax, !tax.isZero {
                    KXSpecRow(String(localized: "account.order.tax", bundle: .module), value: tax.formatted(locale: locale))
                }
                KXDivider()
                HStack {
                    Text("account.order.total", bundle: .module)
                        .kxFont(.headline)
                        .foregroundStyle(KXColor.textPrimary)
                    Spacer()
                    Text(order.totalPrice.formatted(locale: locale))
                        .kxFont(.price)
                        .foregroundStyle(KXColor.textPrimary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("account.order.total")
            }
        }
    }

    private func actions(_ order: CustomerOrder) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.s) {
            KXButton(
                String(localized: "account.order.keys", bundle: .module),
                systemImage: "key",
                isFullWidth: true
            ) {
                onRoute(.account(.licenses(orderID: order.numericID)))
            }
            .accessibilityIdentifier("account.order.keys")
            KXButton(
                String(localized: "account.order.invoice", bundle: .module),
                systemImage: "doc.richtext",
                style: .secondary,
                isFullWidth: true,
                isLoading: model.invoiceState == .loading
            ) {
                Task {
                    if let url = await model.invoiceURL() {
                        openURL(url)
                    }
                }
            }
            .accessibilityIdentifier("account.order.invoice")
            switch model.invoiceState {
            case .byEmail:
                Text("account.order.invoice.email", bundle: .module)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case let .failed(error):
                Text(error.message)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.error)
                    .fixedSize(horizontal: false, vertical: true)
            case .idle, .loading:
                EmptyView()
            }
            KXButton(
                String(localized: "account.order.help", bundle: .module),
                systemImage: "questionmark.bubble",
                style: .tertiary,
                isFullWidth: true
            ) {
                onRoute(.account(.support(orderName: order.name)))
            }
            .accessibilityIdentifier("account.order.help")
        }
    }
}

/// One line of an order.
private struct OrderLineRow: View {
    let line: OrderLineItem
    let locale: Locale

    private static let imageSize: CGFloat = 56

    var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.m) {
            Group {
                if let image = line.image {
                    ProductImage(image, contentMode: .fit, isDecorative: true)
                } else {
                    Image(systemName: "key")
                        .foregroundStyle(KXColor.iconSecondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: Self.imageSize, height: Self.imageSize)
            .background(KXColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous))
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text(line.name)
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let variant = line.variantTitle {
                    Text(variant)
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textSecondary)
                }
                HStack {
                    Text("account.order.quantity \(line.quantity)", bundle: .module)
                        .kxFont(.footnote)
                        .foregroundStyle(KXColor.textSecondary)
                    Spacer()
                    if let total = line.total ?? line.price {
                        Text(total.formatted(locale: locale))
                            .kxFont(.subheadline)
                            .foregroundStyle(KXColor.textPrimary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
