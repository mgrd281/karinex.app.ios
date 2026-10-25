import CommerceUI
import DesignSystem
import Foundation
import Observation
import ShopifyKit
import SwiftUI
import UIKit

// MARK: - AddressCountryOption

/// A country the address form offers: the store's markets, named in the user's language.
public struct AddressCountryOption: Sendable, Hashable, Identifiable {
    /// The ISO code, e.g. `DE`.
    public let code: String
    /// The name, e.g. "Deutschland".
    public let name: String

    /// The code.
    public var id: String {
        code
    }

    /// Creates an option.
    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

// MARK: - AddressesViewModel

/// The customer's addresses and the changes to them.
@MainActor
@Observable
final class AddressesViewModel {
    /// The load state.
    private(set) var state: LoadState<CustomerAddressBook> = .idle
    /// Why the last change failed, with Shopify's own messages.
    private(set) var actionError: UserFacingError?
    /// Whether a change is running.
    private(set) var isSaving = false

    @ObservationIgnored private let repository: any CustomerAccountRepository

    init(repository: any CustomerAccountRepository) {
        self.repository = repository
    }

    /// Loads the addresses.
    func load() async {
        if state.value == nil {
            state = .loading
        }
        do {
            let book = try await repository.addresses()
            state = LoadState(book, isEmpty: { $0.addresses.isEmpty })
        } catch {
            if let failure = UserFacingError(error), state.value == nil {
                state = .failed(failure)
            }
        }
    }

    /// Saves `input`: a new address when `id` is `nil`, else a change. Returns whether it worked.
    func save(_ input: CustomerAddressInput, id: ShopifyID?, makeDefault: Bool) async -> Bool {
        isSaving = true
        actionError = nil
        defer { isSaving = false }
        do {
            if let id {
                _ = try await repository.updateAddress(id: id, with: input, makeDefault: makeDefault)
            } else {
                _ = try await repository.createAddress(input, makeDefault: makeDefault)
            }
            await load()
            return true
        } catch {
            actionError = UserFacingError(error)
            return false
        }
    }

    /// Deletes the address with `id`.
    func delete(_ id: ShopifyID) async {
        isSaving = true
        actionError = nil
        defer { isSaving = false }
        do {
            try await repository.deleteAddress(id: id)
            await load()
        } catch {
            actionError = UserFacingError(error)
        }
    }

    /// Clears ``actionError``.
    func dismissError() {
        actionError = nil
    }
}

// MARK: - AddressesScreen

/// "Adressen": the customer's addresses with the default one marked, editing, deleting and a
/// new address. Validation messages come from Shopify.
public struct AddressesScreen: View {
    private let countries: [AddressCountryOption]

    @State private var model: AddressesViewModel
    @State private var editor: AddressEditor?

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - repository: The Customer Account API.
    ///   - countries: The countries offered in the form.
    public init(repository: any CustomerAccountRepository, countries: [AddressCountryOption]) {
        _model = State(initialValue: AddressesViewModel(repository: repository))
        self.countries = countries
    }

    public var body: some View {
        AsyncContentView(
            model.state,
            empty: AsyncContentEmptyState(
                systemImage: "house",
                title: String(localized: "account.addresses.empty.title", bundle: .module),
                message: String(localized: "account.addresses.empty.message", bundle: .module),
                actionTitle: String(localized: "account.addresses.add", bundle: .module),
                action: { editor = AddressEditor(address: nil, isDefault: false) }
            ),
            retry: { await model.load() },
            content: { book in
                ScrollView {
                    VStack(alignment: .leading, spacing: KXSpacing.m) {
                        ForEach(book.addresses) { address in
                            AddressCard(
                                address: address,
                                isDefault: address.id == book.defaultAddressID,
                                onEdit: { editor = AddressEditor(address: address, isDefault: address.id == book.defaultAddressID) },
                                onDelete: { Task { await model.delete(address.id) } }
                            )
                        }
                        KXButton(
                            String(localized: "account.addresses.add", bundle: .module),
                            systemImage: "plus",
                            style: .secondary,
                            isFullWidth: true
                        ) {
                            editor = AddressEditor(address: nil, isDefault: book.addresses.isEmpty)
                        }
                        .accessibilityIdentifier("account.addresses.add")
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
        .accessibilityIdentifier("screen.addresses")
        .kxScreenBackground()
        .navigationTitle(Text("account.addresses.title", bundle: .module))
        .navigationBarTitleDisplayMode(.large)
        .kxBanner(isPresented: model.actionError != nil && editor == nil) {
            if let error = model.actionError {
                KXBanner(.error, message: error.message, onDismiss: { model.dismissError() })
            }
        }
        .sheet(item: $editor) { editor in
            NavigationStack {
                AddressFormView(editor: editor, countries: countries, model: model) {
                    self.editor = nil
                }
            }
        }
        .task {
            if model.state.value == nil {
                await model.load()
            }
        }
    }
}

/// The address being edited, or a new one.
struct AddressEditor: Identifiable {
    let id = UUID()
    let address: CustomerAddress?
    let isDefault: Bool
}

/// One address with its actions.
private struct AddressCard: View {
    let address: CustomerAddress
    let isDefault: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        KXCard {
            VStack(alignment: .leading, spacing: KXSpacing.s) {
                if isDefault {
                    KXBadge(String(localized: "account.addresses.default", bundle: .module), style: .accent)
                }
                Text(address.lines.joined(separator: "\n"))
                    .kxFont(.body)
                    .foregroundStyle(KXColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: KXSpacing.m) {
                    Button(action: onEdit) {
                        Text("account.addresses.edit", bundle: .module)
                    }
                    .buttonStyle(.kx(.tertiary, size: .compact))
                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        Text("account.addresses.delete", bundle: .module)
                    }
                    .buttonStyle(.kx(.tertiary, size: .compact))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(
            Text("account.addresses.delete.confirm", bundle: .module),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(role: .destructive, action: onDelete) {
                Text("account.addresses.delete", bundle: .module)
            }
        }
    }
}

// MARK: - AddressFormView

/// The form for a new or changed address.
private struct AddressFormView: View {
    let editor: AddressEditor
    let countries: [AddressCountryOption]
    let model: AddressesViewModel
    let onClose: () -> Void

    @State private var input: CustomerAddressInput
    @State private var makeDefault: Bool

    init(editor: AddressEditor, countries: [AddressCountryOption], model: AddressesViewModel, onClose: @escaping () -> Void) {
        self.editor = editor
        self.countries = countries
        self.model = model
        self.onClose = onClose
        var input = editor.address.map(CustomerAddressInput.init(address:)) ?? CustomerAddressInput()
        if input.territoryCode == nil {
            input.territoryCode = countries.first?.code
        }
        _input = State(initialValue: input)
        _makeDefault = State(initialValue: editor.isDefault)
    }

    var body: some View {
        Form {
            Section {
                field(Text("account.address.first_name", bundle: .module), text: $input.firstName, content: .givenName)
                field(Text("account.address.last_name", bundle: .module), text: $input.lastName, content: .familyName)
                field(Text("account.address.company", bundle: .module), text: $input.company, content: .organizationName)
            }
            Section {
                field(Text("account.address.address1", bundle: .module), text: $input.address1, content: .streetAddressLine1)
                field(Text("account.address.address2", bundle: .module), text: $input.address2, content: .streetAddressLine2)
                field(Text("account.address.zip", bundle: .module), text: $input.zip, content: .postalCode)
                field(Text("account.address.city", bundle: .module), text: $input.city, content: .addressCity)
                Picker(selection: Binding(get: { input.territoryCode ?? "" }, set: { input.territoryCode = $0 })) {
                    ForEach(countries) { country in
                        Text(country.name).tag(country.code)
                    }
                } label: {
                    Text("account.address.country", bundle: .module)
                }
            }
            Section {
                Toggle(isOn: $makeDefault) {
                    Text("account.address.default", bundle: .module)
                }
                .tint(KXColor.brand)
            } footer: {
                if let error = model.actionError {
                    Text(error.message)
                        .foregroundStyle(KXColor.error)
                }
            }
        }
        .navigationTitle(
            editor.address == nil
                ? String(localized: "account.address.new", bundle: .module)
                : String(localized: "account.address.edit", bundle: .module)
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    model.dismissError()
                    onClose()
                } label: {
                    Text("account.address.cancel", bundle: .module)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if model.isSaving {
                    ProgressView()
                } else {
                    Button {
                        Task {
                            if await model.save(trimmed(input), id: editor.address?.id, makeDefault: makeDefault) {
                                onClose()
                            }
                        }
                    } label: {
                        Text("account.address.save", bundle: .module)
                    }
                    .accessibilityIdentifier("account.address.save")
                }
            }
        }
    }

    private func field(_ label: Text, text: Binding<String?>, content: UITextContentType) -> some View {
        TextField(
            text: Binding(get: { text.wrappedValue ?? "" }, set: { text.wrappedValue = $0 }),
            label: { label }
        )
        .textContentType(content)
    }

    /// The input with blank fields removed, so Shopify does not store empty strings.
    private func trimmed(_ input: CustomerAddressInput) -> CustomerAddressInput {
        func clean(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        return CustomerAddressInput(
            firstName: clean(input.firstName),
            lastName: clean(input.lastName),
            company: clean(input.company),
            address1: clean(input.address1),
            address2: clean(input.address2),
            zip: clean(input.zip),
            city: clean(input.city),
            zoneCode: clean(input.zoneCode),
            territoryCode: clean(input.territoryCode)
        )
    }
}
