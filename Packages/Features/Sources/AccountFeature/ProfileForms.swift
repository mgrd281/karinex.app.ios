import CommerceUI
import DesignSystem
import Foundation
import ShopifyKit
import SwiftUI
import UIKit

// MARK: - NameFormView

/// "Name ändern": first and last name. The e-mail address is the login and stays as it is.
struct NameFormView: View {
    let model: ProfileViewModel
    /// Called with whether the name was saved.
    let onClose: (Bool) -> Void

    @State private var firstName: String
    @State private var lastName: String

    init(customer: Customer?, model: ProfileViewModel, onClose: @escaping (Bool) -> Void) {
        self.model = model
        self.onClose = onClose
        _firstName = State(initialValue: customer?.firstName ?? "")
        _lastName = State(initialValue: customer?.lastName ?? "")
    }

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField(text: $firstName) {
                    Text("account.address.first_name", bundle: .module)
                }
                .textContentType(.givenName)
                TextField(text: $lastName) {
                    Text("account.address.last_name", bundle: .module)
                }
                .textContentType(.familyName)
            } footer: {
                if let error = model.actionError {
                    Text(error.message)
                        .foregroundStyle(KXColor.error)
                } else {
                    Text("account.profile.name.note", bundle: .module)
                }
            }
        }
        .navigationTitle(Text("account.profile.name.edit", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    model.dismissError()
                    onClose(false)
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
                            if await model.updateName(firstName: firstName, lastName: lastName) {
                                onClose(true)
                            }
                        }
                    } label: {
                        Text("account.address.save", bundle: .module)
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("account.profile.name.save")
                }
            }
        }
    }
}

// MARK: - AddressFormView

/// The form for a new or changed address.
struct AddressFormView: View {
    let editor: AddressEditor
    let countries: [AddressCountryOption]
    let model: ProfileViewModel
    let onClose: () -> Void

    @State private var input: CustomerAddressInput
    @State private var makeDefault: Bool

    init(editor: AddressEditor, countries: [AddressCountryOption], model: ProfileViewModel, onClose: @escaping () -> Void) {
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
