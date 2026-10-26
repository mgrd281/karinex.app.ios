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

// MARK: - ProfileViewModel

/// The customer's personal details: the name and e-mail address for the header and the
/// addresses, with the changes Shopify allows (the name, adding, changing, deleting and the
/// default address).
@MainActor
@Observable
final class ProfileViewModel {
    /// The customer, as far as known.
    private(set) var customer: Customer?
    /// The addresses.
    private(set) var state: LoadState<CustomerAddressBook> = .idle
    /// Why the last change failed, with Shopify's own messages.
    private(set) var actionError: UserFacingError?
    /// Whether a change is running.
    private(set) var isSaving = false

    @ObservationIgnored private let repository: any CustomerAccountRepository

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - repository: The Customer Account API.
    ///   - customer: The customer the app already knows, shown until the fresh one arrives.
    init(repository: any CustomerAccountRepository, customer: Customer? = nil) {
        self.repository = repository
        self.customer = customer
    }

    /// Loads the customer and the addresses together.
    func load() async {
        if state.value == nil {
            state = .loading
        }
        let repository = repository
        async let freshCustomer = try? repository.customer()
        do {
            state = try await .loaded(repository.addresses())
        } catch {
            if let failure = UserFacingError(error), state.value == nil {
                state = .failed(failure)
            }
        }
        if let fresh = await freshCustomer {
            customer = fresh
        }
    }

    /// Changes the name. Returns whether it worked.
    func updateName(firstName: String, lastName: String) async -> Bool {
        isSaving = true
        actionError = nil
        defer { isSaving = false }
        do {
            customer = try await repository.updateName(
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            return true
        } catch {
            actionError = UserFacingError(error)
            return false
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
            await reloadAddresses()
            return true
        } catch {
            actionError = UserFacingError(error)
            return false
        }
    }

    /// Makes `address` the default address.
    func makeDefault(_ address: CustomerAddress) async {
        _ = await save(CustomerAddressInput(address: address), id: address.id, makeDefault: true)
    }

    /// Deletes the address with `id`.
    func delete(_ id: ShopifyID) async {
        isSaving = true
        actionError = nil
        defer { isSaving = false }
        do {
            try await repository.deleteAddress(id: id)
            await reloadAddresses()
        } catch {
            actionError = UserFacingError(error)
        }
    }

    /// Clears ``actionError``.
    func dismissError() {
        actionError = nil
    }

    private func reloadAddresses() async {
        if let book = try? await repository.addresses() {
            state = .loaded(book)
        }
    }
}

// MARK: - ProfileScreen

/// "Persönliche Daten", laid out like the profile pages of fashion retail apps and a step
/// beyond them: the monogram, name, e-mail address and customer number (to copy for support)
/// with "Name ändern"; why there is no password; the addresses as cards side by side with the
/// default one marked, "Als Standard festlegen", editing, deleting and a card for a new
/// address; then "Konto und Daten löschen" and "Abmelden". Validation messages come from
/// Shopify.
public struct ProfileScreen: View {
    private let countries: [AddressCountryOption]
    private let sessionStore: CustomerSessionStore
    private let onRoute: @MainActor (CommerceRoute) -> Void

    @State private var model: ProfileViewModel
    @State private var addressEditor: AddressEditor?
    @State private var isNameEditorPresented = false
    @State private var isSignOutConfirmationPresented = false

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - repository: The Customer Account API.
    ///   - countries: The countries offered in the address form.
    ///   - sessionStore: The login state, for the known customer and "Abmelden".
    ///   - onRoute: Opens the account deletion and returns to the Konto tab after signing out.
    public init(
        repository: any CustomerAccountRepository,
        countries: [AddressCountryOption],
        sessionStore: CustomerSessionStore,
        onRoute: @escaping @MainActor (CommerceRoute) -> Void
    ) {
        _model = State(initialValue: ProfileViewModel(repository: repository, customer: sessionStore.customer))
        self.countries = countries
        self.sessionStore = sessionStore
        self.onRoute = onRoute
    }

    public var body: some View {
        AsyncContentView(
            model.state,
            retry: { await model.load() },
            content: { book in
                ScrollView {
                    VStack(alignment: .leading, spacing: KXSpacing.xl) {
                        header
                            .padding(.horizontal, KXSpacing.gutter)
                        ProfileLoginNote()
                            .padding(.horizontal, KXSpacing.gutter)
                        addresses(book)
                        accountSection
                            .padding(.horizontal, KXSpacing.gutter)
                    }
                    .padding(.vertical, KXSpacing.m)
                }
                .refreshable { await model.load() }
            },
            placeholder: {
                AsyncContentSkeleton()
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.profile")
        .kxScreenBackground()
        .navigationTitle(Text("account.profile.screen.title", bundle: .module))
        .navigationBarTitleDisplayMode(.large)
        .kxBanner(isPresented: model.actionError != nil && addressEditor == nil && !isNameEditorPresented) {
            if let error = model.actionError {
                KXBanner(.error, message: error.message, onDismiss: { model.dismissError() })
            }
        }
        .sheet(item: $addressEditor) { editor in
            NavigationStack {
                AddressFormView(editor: editor, countries: countries, model: model) {
                    addressEditor = nil
                }
            }
        }
        .sheet(isPresented: $isNameEditorPresented) {
            NavigationStack {
                NameFormView(customer: model.customer, model: model) { didSave in
                    isNameEditorPresented = false
                    if didSave {
                        Task { await sessionStore.loadCustomer() }
                    }
                }
            }
        }
        .confirmationDialog(
            Text("account.signout.confirm.title", bundle: .module),
            isPresented: $isSignOutConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task {
                    await AccountLogin.signOut(sessionStore)
                    onRoute(.account(.overview))
                }
            } label: {
                Text("account.signout", bundle: .module)
            }
        }
        .task {
            if model.state.value == nil {
                await model.load()
            }
        }
    }

    // MARK: Header

    /// The monogram, name, e-mail address and customer number, with "Name ändern".
    private var header: some View {
        let customer = model.customer
        return HStack(alignment: .top, spacing: KXSpacing.m) {
            ProfileMonogram(initials: ProfileName.initials(of: customer))
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Group {
                    if let name = ProfileName.displayName(of: customer) {
                        Text(verbatim: name)
                    } else {
                        Text("account.profile.title", bundle: .module)
                    }
                }
                .kxFont(.title2)
                .foregroundStyle(KXColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                if let email = customer?.emailAddress {
                    Text(verbatim: email)
                        .kxFont(.subheadline)
                        .foregroundStyle(KXColor.textSecondary)
                        .textSelection(.enabled)
                }
                if let number = customer?.id.resourceID {
                    ProfileCustomerNumber(number: number)
                        .padding(.top, KXSpacing.xxs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ProfileCircleButton(
                systemImage: "pencil",
                label: Text("account.profile.name.edit", bundle: .module)
            ) {
                model.dismissError()
                isNameEditorPresented = true
            }
            .accessibilityIdentifier("account.profile.name.edit")
        }
    }

    // MARK: Addresses

    /// The heading with "Adresse hinzufügen" and the cards side by side.
    private func addresses(_ book: CustomerAddressBook) -> some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: KXSpacing.m) {
                Text("account.addresses.title", bundle: .module)
                    .kxFont(.title3)
                    .foregroundStyle(KXColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    model.dismissError()
                    addressEditor = AddressEditor(address: nil, isDefault: book.addresses.isEmpty)
                } label: {
                    Label {
                        Text("account.addresses.add", bundle: .module)
                    } icon: {
                        Image(systemName: "plus")
                    }
                    .fontWeight(.semibold)
                    .kxFont(.subheadline)
                    .foregroundStyle(KXColor.textPrimary)
                    .frame(minHeight: KXSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account.addresses.add")
            }
            .padding(.horizontal, KXSpacing.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: KXSpacing.s) {
                    ForEach(book.addresses) { address in
                        let isDefault = address.id == book.defaultAddressID
                        AddressCard(
                            address: address,
                            isDefault: isDefault,
                            isSaving: model.isSaving,
                            onMakeDefault: { Task { await model.makeDefault(address) } },
                            onEdit: {
                                model.dismissError()
                                addressEditor = AddressEditor(address: address, isDefault: isDefault)
                            },
                            onDelete: { Task { await model.delete(address.id) } }
                        )
                        .containerRelativeFrame(.horizontal) { width, _ in
                            ProfileLayout.cardWidth(in: width)
                        }
                    }
                    NewAddressCard {
                        model.dismissError()
                        addressEditor = AddressEditor(address: nil, isDefault: book.addresses.isEmpty)
                    }
                    .containerRelativeFrame(.horizontal) { width, _ in
                        ProfileLayout.cardWidth(in: width)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, KXSpacing.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("account.addresses")
        }
    }

    // MARK: Account

    /// "Konto und Daten löschen" and "Abmelden".
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: KXSpacing.l) {
            VStack(alignment: .leading, spacing: 0) {
                KXDivider()
                Button {
                    onRoute(.account(.deleteAccount))
                } label: {
                    HStack(spacing: KXSpacing.m) {
                        Image(systemName: "trash")
                            .fontWeight(.light)
                            .kxFont(.title3)
                            .foregroundStyle(KXColor.textPrimary)
                            .frame(width: KXSpacing.xl)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                            Text("account.profile.delete.title", bundle: .module)
                                .kxFont(.headline)
                                .foregroundStyle(KXColor.textPrimary)
                            Text("account.profile.delete.subtitle", bundle: .module)
                                .kxFont(.subheadline)
                                .foregroundStyle(KXColor.textSecondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .fontWeight(.medium)
                            .kxFont(.footnote)
                            .foregroundStyle(KXColor.iconSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, KXSpacing.m)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account.profile.delete")
                KXDivider()
            }
            KXButton(
                String(localized: "account.signout", bundle: .module),
                systemImage: "rectangle.portrait.and.arrow.right",
                isFullWidth: true
            ) {
                isSignOutConfirmationPresented = true
            }
            .accessibilityIdentifier("account.profile.signout")
        }
    }
}

// MARK: - ProfileLayout

/// Sizes of the profile page.
enum ProfileLayout {
    /// The width of an address card: most of the page, so the next card peeks in, at most 340
    /// points on wide screens.
    static func cardWidth(in width: CGFloat) -> CGFloat {
        min(width * 0.8, 340)
    }
}

// MARK: - ProfileName

/// The name and initials shown for a customer.
enum ProfileName {
    /// "Anna Schmidt" from the first and last name, else Shopify's display name when it is not
    /// just the e-mail address; `nil` without either.
    static func displayName(of customer: Customer?) -> String? {
        guard let customer else { return nil }
        let name = [customer.firstName, customer.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !name.isEmpty {
            return name
        }
        let display = customer.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return display.isEmpty || display == customer.emailAddress ? nil : display
    }

    /// Up to two initials ("AS"), the first letter of the e-mail address without a name, empty
    /// without either.
    static func initials(of customer: Customer?) -> String {
        if let name = displayName(of: customer) {
            let words = name.split(whereSeparator: \.isWhitespace)
            let letters = [words.first, words.count > 1 ? words.last : nil].compactMap { $0?.first }
            return String(letters).uppercased()
        }
        return customer?.emailAddress?.first.map { String($0).uppercased() } ?? ""
    }
}

// MARK: - ProfileMonogram

/// The initials on an ink disc, or the person symbol without them. Decorative.
struct ProfileMonogram: View {
    let initials: String

    @ScaledMetric(relativeTo: .title2) private var side: CGFloat = 56

    var body: some View {
        Group {
            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .kxFont(.title2)
            } else {
                Text(verbatim: initials)
                    .kxFont(.title3)
                    .minimumScaleFactor(0.6)
            }
        }
        .foregroundStyle(KXColor.textOnBrand)
        .frame(width: min(side, 80), height: min(side, 80))
        .background(KXColor.brand, in: Circle())
        .accessibilityHidden(true)
    }
}

// MARK: - ProfileCustomerNumber

/// "Kundennummer 3029680329" with a button that copies the number for a support request.
private struct ProfileCustomerNumber: View {
    let number: String

    @State private var copies = 0
    @State private var isCopied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = number
            copies += 1
            isCopied = true
        } label: {
            HStack(spacing: KXSpacing.xxs) {
                Text("account.profile.number \(number)", bundle: .module)
                    .monospacedDigit()
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .kxFont(.footnote)
            .foregroundStyle(KXColor.textSecondary)
            .frame(minHeight: KXSpacing.minimumTapTarget / 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: copies)
        .accessibilityHint(Text("account.profile.number.copy", bundle: .module))
        .accessibilityIdentifier("account.profile.number")
        .task(id: copies) {
            guard isCopied else { return }
            try? await Task.sleep(for: .seconds(2))
            isCopied = false
        }
    }
}

// MARK: - ProfileLoginNote

/// Why there is no password to change: every login is a code sent by e-mail.
private struct ProfileLoginNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: KXSpacing.s) {
            Image(systemName: "lock.shield")
                .fontWeight(.light)
                .kxFont(.title3)
                .foregroundStyle(KXColor.textPrimary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                Text("account.profile.login.title", bundle: .module)
                    .kxFont(.headline)
                    .foregroundStyle(KXColor.textPrimary)
                Text("account.profile.login.message", bundle: .module)
                    .kxFont(.subheadline)
                    .foregroundStyle(KXColor.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(KXSpacing.m)
        .background(KXColor.surface, in: RoundedRectangle(cornerRadius: KXRadius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ProfileCircleButton

/// A symbol in an outlined circle, like the edit buttons of fashion retail apps.
private struct ProfileCircleButton: View {
    let systemImage: String
    let label: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .kxFont(.body)
                .foregroundStyle(KXColor.textPrimary)
                .frame(width: KXSpacing.minimumTapTarget, height: KXSpacing.minimumTapTarget)
                .overlay {
                    Circle()
                        .strokeBorder(KXColor.textPrimary, lineWidth: KXBorder.regular)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - AddressEditor

/// The address being edited, or a new one.
struct AddressEditor: Identifiable {
    let id = UUID()
    let address: CustomerAddress?
    let isDefault: Bool
}

// MARK: - AddressCard

/// One address as a card: "Standardadresse" or "Als Standard festlegen", the name and the
/// address, and the edit and delete buttons. The default address has an ink outline.
private struct AddressCard: View {
    let address: CustomerAddress
    let isDefault: Bool
    let isSaving: Bool
    let onMakeDefault: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        let lines = address.lines
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            if isDefault {
                KXBadge(String(localized: "account.addresses.default", bundle: .module), systemImage: "checkmark")
            } else {
                Button(action: onMakeDefault) {
                    Text("account.addresses.make_default", bundle: .module)
                        .fontWeight(.semibold)
                        .kxFont(.footnote)
                        .underline()
                        .foregroundStyle(KXColor.textPrimary)
                        .frame(minHeight: KXSpacing.minimumTapTarget / 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .accessibilityIdentifier("account.addresses.makeDefault")
            }
            VStack(alignment: .leading, spacing: KXSpacing.xxs) {
                if let first = lines.first {
                    Text(verbatim: first)
                        .kxFont(.headline)
                        .foregroundStyle(KXColor.textPrimary)
                }
                ForEach(Array(lines.dropFirst().enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .kxFont(.body)
                        .foregroundStyle(KXColor.textPrimary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            HStack(spacing: KXSpacing.s) {
                ProfileCircleButton(systemImage: "pencil", label: Text("account.address.edit", bundle: .module), action: onEdit)
                    .accessibilityIdentifier("account.addresses.edit")
                ProfileCircleButton(systemImage: "trash", label: Text("account.addresses.delete", bundle: .module)) {
                    isDeleteConfirmationPresented = true
                }
                .accessibilityIdentifier("account.addresses.delete")
            }
        }
        .padding(KXSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KXColor.background, in: RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous)
                .strokeBorder(
                    isDefault ? KXColor.textPrimary : KXColor.hairline,
                    lineWidth: isDefault ? KXBorder.emphasis : KXBorder.hairline
                )
        }
        .accessibilityElement(children: .contain)
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

// MARK: - NewAddressCard

/// The last card: a dashed outline with a plus and "Neue Adresse".
private struct NewAddressCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: KXSpacing.s) {
                Image(systemName: "plus")
                    .kxFont(.title2)
                    .frame(width: KXSpacing.minimumTapTarget, height: KXSpacing.minimumTapTarget)
                    .background(KXColor.surface, in: Circle())
                Text("account.address.new", bundle: .module)
                    .fontWeight(.semibold)
                    .kxFont(.subheadline)
            }
            .foregroundStyle(KXColor.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: KXSpacing.xxxl * 2)
            .overlay {
                RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous)
                    .strokeBorder(KXColor.divider, style: StrokeStyle(lineWidth: KXBorder.regular, dash: [KXSpacing.xxs, KXSpacing.xxs]))
            }
            .contentShape(RoundedRectangle(cornerRadius: KXRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("account.addresses.new")
    }
}
