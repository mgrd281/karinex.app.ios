import BackendKit
import CommerceUI
import DesignSystem
import Foundation
import Observation
import QuickLook
import ShopifyKit
import SwiftUI

// MARK: - InvoicePDF

/// Loads an invoice PDF from the backend's short-lived signed link into the app's temporary
/// folder, so it opens natively in Quick Look (share, print, save to Files) and never in a
/// browser (PROMPT.md hard rule 3).
enum InvoicePDF {
    /// The local file name, e.g. `Rechnung-3689.pdf`.
    static func fileName(orderName: String) -> String {
        let number = orderName.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "Rechnung-\(number.isEmpty ? "KARINEX" : number).pdf"
    }

    /// Downloads the PDF behind `link` and returns the local file.
    static func download(_ link: URL, orderName: String, session: URLSession = .shared) async throws -> URL {
        let (data, response) = try await session.data(from: link)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.starts(with: Array("%PDF".utf8)) else {
            throw URLError(.cannotDecodeContentData)
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Invoices", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(fileName(orderName: orderName))
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        return file
    }
}

// MARK: - InvoicesViewModel

/// "Rechnungen": the orders that have an invoice in the backend, newest first, with their date
/// and total from Shopify. Opening one downloads the PDF for Quick Look.
@MainActor
@Observable
final class InvoicesViewModel {
    /// Orders that are read to find the invoices.
    static let pageSize = 50

    /// One invoice row.
    struct Item: Identifiable, Equatable {
        let order: CustomerOrder
        var id: ShopifyID {
            order.id
        }
    }

    /// The list.
    private(set) var state: LoadState<[Item]> = .idle
    /// The order whose PDF is loading.
    private(set) var openingID: ShopifyID?
    /// Why the last PDF could not be opened.
    private(set) var openError: UserFacingError?
    /// The downloaded PDF shown in Quick Look.
    var preview: URL?

    @ObservationIgnored private let repository: any CustomerAccountRepository
    @ObservationIgnored private let backend: any BackendClient

    init(repository: any CustomerAccountRepository, backend: any BackendClient) {
        self.repository = repository
        self.backend = backend
    }

    /// Loads the orders and which of them have an invoice.
    func load() async {
        if state.value == nil {
            state = .loading
        }
        let repository = repository
        let backend = backend
        async let statuses = backend.orders()
        do {
            let page = try await repository.orders(first: Self.pageSize, after: nil)
            let withInvoice: Set<String>
            do {
                let reported = try await statuses
                withInvoice = Set(reported.filter(\.hasInvoice).map(\.orderID))
            } catch BackendError.notConfigured {
                withInvoice = []
            }
            let items = page.orders.filter { $0.numericID.map(withInvoice.contains) ?? false }.map(Item.init)
            state = LoadState(items, isEmpty: \.isEmpty)
        } catch {
            if let failure = UserFacingError(error), state.value == nil {
                state = .failed(failure)
            }
        }
    }

    /// Downloads the PDF of `item` and shows it.
    func open(_ item: Item) async {
        guard openingID == nil, let numericID = item.order.numericID else { return }
        openingID = item.id
        openError = nil
        defer { openingID = nil }
        do {
            let link = try await backend.invoice(orderID: numericID)
            preview = try await InvoicePDF.download(link.url, orderName: item.order.name)
        } catch {
            openError = UserFacingError(error) ?? UserFacingError(URLError(.cannotDecodeContentData))
        }
    }

    /// Clears the error after it was shown.
    func dismissError() {
        openError = nil
    }
}

// MARK: - InvoicesScreen

/// "Rechnungen": every invoice of the customer as a row with the order number, date and total;
/// a tap opens the PDF in Quick Look.
public struct InvoicesScreen: View {
    private let onRoute: @MainActor (CommerceRoute) -> Void

    @State private var model: InvoicesViewModel

    @Environment(\.locale) private var locale

    /// Creates the list.
    public init(
        repository: any CustomerAccountRepository,
        backend: any BackendClient,
        onRoute: @escaping @MainActor (CommerceRoute) -> Void
    ) {
        _model = State(initialValue: InvoicesViewModel(repository: repository, backend: backend))
        self.onRoute = onRoute
    }

    public var body: some View {
        AsyncContentView(
            model.state,
            empty: AsyncContentEmptyState(
                systemImage: "doc.richtext",
                title: String(localized: "account.invoices.empty.title", bundle: .module),
                message: String(localized: "account.invoices.empty.message", bundle: .module)
            ),
            retry: { await model.load() },
            content: { items in
                ScrollView {
                    VStack(alignment: .leading, spacing: KXSpacing.l) {
                        KXListGroup {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 {
                                    KXListDivider()
                                }
                                row(item)
                            }
                        } footer: {
                            Text("account.invoices.footnote", bundle: .module)
                        }
                    }
                    .padding(.horizontal, KXSpacing.gutter)
                    .padding(.vertical, KXSpacing.m)
                    .kxReadableWidth()
                }
                .refreshable { await model.load() }
            }
        )
        .accessibilityIdentifier("screen.invoices")
        .kxScreenBackground()
        .navigationTitle(Text("account.invoices.title", bundle: .module))
        .navigationBarTitleDisplayMode(.large)
        .task {
            if model.state.value == nil {
                await model.load()
            }
        }
        .quickLookPreview($model.preview)
        .alert(
            Text("account.invoices.error.title", bundle: .module),
            isPresented: Binding(get: { model.openError != nil }, set: { if !$0 { model.dismissError() } }),
            presenting: model.openError
        ) { _ in
            Button(role: .cancel) {
                model.dismissError()
            } label: {
                Text("account.signin.error.close", bundle: .module)
            }
        } message: { error in
            Text(error.message)
        }
    }

    private func row(_ item: InvoicesViewModel.Item) -> some View {
        let order = item.order
        let date = order.processedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
        return Button {
            Task { await model.open(item) }
        } label: {
            ZStack(alignment: .trailing) {
                KXListRow(
                    systemImage: "doc.richtext",
                    title: Text("account.invoices.row \(order.name)", bundle: .module),
                    detail: Text(verbatim: date),
                    value: order.totalPrice.formatted(locale: locale),
                    accessory: model.openingID == item.id ? .none : .chevron
                )
                if model.openingID == item.id {
                    ProgressView()
                        .padding(.trailing, KXSpacing.m)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.openingID != nil)
        .accessibilityHint(Text("account.invoices.open.hint", bundle: .module))
        .accessibilityIdentifier("account.invoices.row")
    }
}
