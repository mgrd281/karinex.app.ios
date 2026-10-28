import BackendKit
import CommerceUI
import DesignSystem
import Foundation
import Observation
import QuickLook
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

/// "Bestellungen": every order as a card with its status, date, the photos of its products,
/// the order number with the first product and the total.
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
                                OrderCard(
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

/// One order in the list: the status and the date, the photos of up to four products (a plus
/// tile when there are more), then the order number with the first product and the total.
private struct OrderCard: View {
    /// The most photos a card shows.
    static let maximumPhotos = 4

    let order: CustomerOrder
    let pill: OrderStatusPill
    let locale: Locale

    @ScaledMetric(relativeTo: .body) private var photoSide: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: KXSpacing.s) {
                KXBadge(pill.title, style: pill.style)
                Spacer(minLength: KXSpacing.s)
                Text(order.processedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)))
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.textSecondary)
            }
            if !order.lineItems.isEmpty {
                photos
            }
            HStack(alignment: .center, spacing: KXSpacing.s) {
                VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                    Text(order.name)
                        .kxFont(.headline)
                        .foregroundStyle(KXColor.textPrimary)
                    if let first = order.lineItems.first {
                        Text(first.name)
                            .kxFont(.subheadline)
                            .foregroundStyle(KXColor.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(order.totalPrice.formatted(locale: locale))
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.textPrimary)
                Image(systemName: "chevron.right")
                    .fontWeight(.medium)
                    .kxFont(.footnote)
                    .foregroundStyle(KXColor.iconSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(KXSpacing.m)
        .background(KXColor.background, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous)
                .strokeBorder(KXColor.hairline, lineWidth: KXBorder.hairline)
        }
        .contentShape(RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// The product photos on light tiles.
    private var photos: some View {
        let side = min(photoSide, 96)
        return HStack(spacing: KXSpacing.xs) {
            ForEach(order.lineItems.prefix(Self.maximumPhotos)) { line in
                Group {
                    if let image = line.image {
                        ProductImage(image, contentMode: .fit, isDecorative: true)
                            .padding(KXSpacing.xxs)
                    } else {
                        Image(systemName: "key")
                            .foregroundStyle(KXColor.imageIcon)
                    }
                }
                .frame(width: side, height: side)
                .kxPhotoTile()
                .clipShape(RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous))
                .accessibilityHidden(true)
            }
            if order.lineItems.count > Self.maximumPhotos {
                Image(systemName: "plus")
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.textSecondary)
                    .frame(width: side, height: side)
                    .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous))
                    .accessibilityHidden(true)
            }
        }
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

    /// Requests the short-lived invoice link and downloads the PDF for Quick Look; `nil` when
    /// there is none to open.
    func invoiceFile() async -> URL? {
        guard let order = state.value, let numericID = order.numericID else { return nil }
        invoiceState = .loading
        do {
            let link = try await backend.invoice(orderID: numericID)
            let file = try await InvoicePDF.download(link.url, orderName: order.name)
            invoiceState = .idle
            return file
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
/// returns them, "Erneut kaufen" (the same products and quantities back into the cart),
/// "Lizenzschlüssel anzeigen", "Rechnung (PDF)" and help with this order.
public struct OrderDetailScreen: View {
    private let onRoute: @MainActor (CommerceRoute) -> Void
    private let onReorder: (@MainActor ([OrderLineItem]) async -> Void)?

    @State private var model: OrderDetailViewModel
    @State private var isReordering = false

    @Environment(\.locale) private var locale
    @Environment(\.productLookup) private var productLookup
    @State private var invoicePreview: URL?

    /// Creates the screen.
    public init(
        orderID: ShopifyID,
        repository: any CustomerAccountRepository,
        backend: any BackendClient,
        onRoute: @escaping @MainActor (CommerceRoute) -> Void,
        onReorder: (@MainActor ([OrderLineItem]) async -> Void)? = nil
    ) {
        _model = State(initialValue: OrderDetailViewModel(orderID: orderID, repository: repository, backend: backend))
        self.onRoute = onRoute
        self.onReorder = onReorder
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
        .quickLookPreview($invoicePreview)
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
                        if let productID = line.productID {
                            Button {
                                Task { await openProduct(productID) }
                            } label: {
                                OrderLineRow(line: line, locale: locale, opensProduct: true)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("account.order.line.open", bundle: .module))
                            .accessibilityIdentifier("account.order.line")
                        } else {
                            OrderLineRow(line: line, locale: locale, opensProduct: false)
                        }
                        if line.id != order.lineItems.last?.id {
                            KXDivider()
                        }
                    }
                }
            }
        }
    }

    /// Opens the product screen of a line: the product is looked up by its ID in the current
    /// market; a product that no longer exists leaves the order as it is.
    private func openProduct(_ id: ShopifyID) async {
        guard let lookup = productLookup,
              let product = try? await lookup.products(ids: [id]).first
        else { return }
        onRoute(.product(handle: product.handle))
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
        let reorderable = OrderReorder.lines(of: order)
        return VStack(alignment: .leading, spacing: KXSpacing.s) {
            if let onReorder, !reorderable.isEmpty {
                KXButton(
                    String(localized: "account.order.reorder", bundle: .module),
                    systemImage: "arrow.clockwise",
                    isFullWidth: true,
                    isLoading: isReordering
                ) {
                    Task {
                        isReordering = true
                        await onReorder(reorderable)
                        isReordering = false
                    }
                }
                .disabled(isReordering)
                .accessibilityIdentifier("account.order.reorder")
            }
            KXButton(
                String(localized: "account.order.keys", bundle: .module),
                systemImage: "key",
                style: .secondary,
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
                    invoicePreview = await model.invoiceFile()
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

// MARK: - OrderReorder

/// "Erneut kaufen": the lines of an order that can go back into the cart.
enum OrderReorder {
    /// The lines with a variant that still exists; custom lines and deleted variants are left
    /// out. Each line goes into the cart with its quantity.
    static func lines(of order: CustomerOrder) -> [OrderLineItem] {
        order.lineItems.filter { $0.variantID != nil && $0.quantity > 0 }
    }
}

/// One line of an order.
private struct OrderLineRow: View {
    let line: OrderLineItem
    let locale: Locale
    /// Whether a tap opens the product: the row then ends with a chevron.
    let opensProduct: Bool

    private static let imageSize: CGFloat = 56

    var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.m) {
            Group {
                if let image = line.image {
                    ProductImage(image, contentMode: .fit, isDecorative: true)
                } else {
                    Image(systemName: "key")
                        .foregroundStyle(KXColor.imageIcon)
                        .accessibilityHidden(true)
                }
            }
            .kxPhotoTile()
            .frame(width: Self.imageSize, height: Self.imageSize)
            .clipShape(RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous))
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
            if opensProduct {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(KXColor.iconSecondary)
                    .padding(.top, KXSpacing.xs)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
