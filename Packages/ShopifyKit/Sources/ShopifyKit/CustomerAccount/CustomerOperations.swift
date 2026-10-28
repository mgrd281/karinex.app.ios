import Foundation

// MARK: - CustomerFragments

/// Fragments of the Customer Account API documents. Only fields documented for the pinned
/// API version are selected; personal data beyond what the account screens show is never
/// requested.
public enum CustomerFragments {
    /// `CustomerAddressFields` on `CustomerAddress`.
    public static let address = """
        fragment CustomerAddressFields on CustomerAddress {
          id
          firstName
          lastName
          company
          address1
          address2
          zip
          city
          province
          zoneCode
          country
          territoryCode
        }
        """

    /// `CustomerMoneyFields` on `MoneyV2`.
    public static let money = """
        fragment CustomerMoneyFields on MoneyV2 {
          amount
          currencyCode
        }
        """

    /// `OrderSummaryFields` on `Order`: what the order list shows.
    public static let orderSummary = """
        fragment OrderSummaryFields on Order {
          id
          name
          confirmationNumber
          processedAt
          cancelledAt
          financialStatus
          fulfillmentStatus
          totalPrice {
            ...CustomerMoneyFields
          }
        }
        """

    /// `OrderDetailFields` on `Order`: totals, line items and fulfillments.
    public static let orderDetail = """
        fragment OrderDetailFields on Order {
          ...OrderSummaryFields
          subtotal {
            ...CustomerMoneyFields
          }
          totalTax {
            ...CustomerMoneyFields
          }
          totalShipping {
            ...CustomerMoneyFields
          }
          lineItems(first: 50) {
            nodes {
              id
              name
              presentmentTitle
              variantId
              productId
              quantity
              price {
                ...CustomerMoneyFields
              }
              currentTotalPrice {
                ...CustomerMoneyFields
              }
              image {
                url
                altText
                width
                height
              }
            }
          }
          fulfillments(first: 20) {
            nodes {
              id
              status
              latestShipmentStatus
              updatedAt
            }
          }
        }
        """

    static func document(_ operation: String, fragments: [String]) -> String {
        ([operation] + fragments).joined(separator: "\n\n") + "\n"
    }
}

// MARK: - CustomerQuery

/// The signed-in customer with the default address.
public struct CustomerQuery: GraphQLOperation {
    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The customer.
        public let customer: Customer
    }

    /// `Customer`.
    public static let operationName = "Customer"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation and its fragments.
    public static let document = CustomerFragments.document(
        """
        query Customer {
          customer {
            id
            displayName
            firstName
            lastName
            emailAddress {
              emailAddress
            }
            defaultAddress {
              ...CustomerAddressFields
            }
          }
        }
        """,
        fragments: [CustomerFragments.address]
    )

    /// Creates the query.
    public init() {}
}

// MARK: - CustomerOrdersQuery

/// One page of the customer's orders, newest first.
public struct CustomerOrdersQuery: GraphQLOperation {
    /// The largest page size the app requests.
    public static let maximumPageSize = 50

    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The page size.
        public let first: Int
        /// The cursor of the previous page.
        public let after: String?
    }

    /// The customer with one page of orders.
    public struct CustomerOrders: Decodable, Sendable, Equatable {
        /// The orders.
        public let orders: Connection<CustomerOrder>
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The customer.
        public let customer: CustomerOrders
    }

    /// `CustomerOrders`.
    public static let operationName = "CustomerOrders"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation and its fragments.
    public static let document = CustomerFragments.document(
        """
        query CustomerOrders($first: Int!, $after: String) {
          customer {
            orders(first: $first, after: $after, sortKey: PROCESSED_AT, reverse: true) {
              nodes {
                ...OrderSummaryFields
                lineItems(first: 5) {
                  nodes {
                    id
                    name
                    quantity
                    image {
                      url
                      altText
                      width
                      height
                    }
                  }
                }
              }
              pageInfo {
                hasNextPage
                hasPreviousPage
                startCursor
                endCursor
              }
            }
          }
        }
        """,
        fragments: [CustomerFragments.orderSummary, CustomerFragments.money]
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the query; `first` is clamped to 1...50.
    public init(first: Int, after: String? = nil) {
        variables = Variables(first: min(max(first, 1), Self.maximumPageSize), after: after)
    }
}

// MARK: - CustomerOrderQuery

/// One order with totals, line items and fulfillments.
public struct CustomerOrderQuery: GraphQLOperation {
    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The order GID.
        public let id: ShopifyID
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The order, `nil` when it does not belong to the customer.
        public let order: CustomerOrder?
    }

    /// `CustomerOrder`.
    public static let operationName = "CustomerOrder"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation and its fragments.
    public static let document = CustomerFragments.document(
        """
        query CustomerOrder($id: ID!) {
          order(id: $id) {
            ...OrderDetailFields
          }
        }
        """,
        fragments: [CustomerFragments.orderDetail, CustomerFragments.orderSummary, CustomerFragments.money]
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the query.
    public init(id: ShopifyID) {
        variables = Variables(id: id)
    }
}

// MARK: - CustomerAddressesQuery

/// The customer's addresses and the ID of the default one.
public struct CustomerAddressesQuery: GraphQLOperation {
    /// The default address reference.
    public struct AddressReference: Decodable, Sendable, Equatable {
        /// The address GID.
        public let id: ShopifyID
    }

    /// The customer with the addresses.
    public struct CustomerAddresses: Decodable, Sendable, Equatable {
        /// The addresses.
        public let addresses: Connection<CustomerAddress>
        /// The default address.
        public let defaultAddress: AddressReference?
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The customer.
        public let customer: CustomerAddresses
    }

    /// `CustomerAddresses`.
    public static let operationName = "CustomerAddresses"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation and its fragments.
    public static let document = CustomerFragments.document(
        """
        query CustomerAddresses {
          customer {
            addresses(first: 20) {
              nodes {
                ...CustomerAddressFields
              }
            }
            defaultAddress {
              id
            }
          }
        }
        """,
        fragments: [CustomerFragments.address]
    )

    /// Creates the query.
    public init() {}
}

// MARK: - Address mutations

/// The payload of `customerAddressCreate` and `customerAddressUpdate`.
public struct CustomerAddressPayload: Decodable, Sendable, Equatable, UserErrorsPayload {
    /// The created or changed address.
    public let customerAddress: CustomerAddress?
    /// Validation errors with Shopify's localized messages.
    public let userErrors: [UserError]
}

/// The payload of `customerAddressDelete`.
public struct CustomerAddressDeletePayload: Decodable, Sendable, Equatable, UserErrorsPayload {
    /// The GID of the deleted address.
    public let deletedAddressId: ShopifyID?
    /// Errors with Shopify's localized messages.
    public let userErrors: [UserError]
}

/// Adds an address (`customerAddressCreate`).
public struct CustomerAddressCreateMutation: GraphQLOperation {
    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The address.
        public let address: CustomerAddressInput
        /// Whether it becomes the default address.
        public let defaultAddress: Bool
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The payload.
        public let customerAddressCreate: CustomerAddressPayload
    }

    /// `CustomerAddressCreate`.
    public static let operationName = "CustomerAddressCreate"
    /// A mutation.
    public static let kind = GraphQLOperationKind.mutation
    /// The operation and its fragments.
    public static let document = CustomerFragments.document(
        """
        mutation CustomerAddressCreate($address: CustomerAddressInput!, $defaultAddress: Boolean) {
          customerAddressCreate(address: $address, defaultAddress: $defaultAddress) {
            customerAddress {
              ...CustomerAddressFields
            }
            userErrors {
              field
              message
              code
            }
          }
        }
        """,
        fragments: [CustomerFragments.address]
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the mutation.
    public init(address: CustomerAddressInput, defaultAddress: Bool) {
        variables = Variables(address: address, defaultAddress: defaultAddress)
    }
}

/// Changes an address (`customerAddressUpdate`).
public struct CustomerAddressUpdateMutation: GraphQLOperation {
    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The address GID.
        public let addressId: ShopifyID
        /// The new values.
        public let address: CustomerAddressInput
        /// Whether it becomes the default address.
        public let defaultAddress: Bool
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The payload.
        public let customerAddressUpdate: CustomerAddressPayload
    }

    /// `CustomerAddressUpdate`.
    public static let operationName = "CustomerAddressUpdate"
    /// A mutation.
    public static let kind = GraphQLOperationKind.mutation
    /// The operation and its fragments.
    public static let document = CustomerFragments.document(
        """
        mutation CustomerAddressUpdate($addressId: ID!, $address: CustomerAddressInput, $defaultAddress: Boolean) {
          customerAddressUpdate(addressId: $addressId, address: $address, defaultAddress: $defaultAddress) {
            customerAddress {
              ...CustomerAddressFields
            }
            userErrors {
              field
              message
              code
            }
          }
        }
        """,
        fragments: [CustomerFragments.address]
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the mutation.
    public init(addressID: ShopifyID, address: CustomerAddressInput, defaultAddress: Bool) {
        variables = Variables(addressId: addressID, address: address, defaultAddress: defaultAddress)
    }
}

/// Deletes an address (`customerAddressDelete`).
public struct CustomerAddressDeleteMutation: GraphQLOperation {
    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The address GID.
        public let addressId: ShopifyID
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The payload.
        public let customerAddressDelete: CustomerAddressDeletePayload
    }

    /// `CustomerAddressDelete`.
    public static let operationName = "CustomerAddressDelete"
    /// A mutation.
    public static let kind = GraphQLOperationKind.mutation
    /// The operation and its fragments.
    public static let document = CustomerFragments.document(
        """
        mutation CustomerAddressDelete($addressId: ID!) {
          customerAddressDelete(addressId: $addressId) {
            deletedAddressId
            userErrors {
              field
              message
              code
            }
          }
        }
        """,
        fragments: []
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the mutation.
    public init(addressID: ShopifyID) {
        variables = Variables(addressId: addressID)
    }
}

// MARK: - CustomerUpdateMutation

/// The payload of `customerUpdate`.
public struct CustomerUpdatePayload: Decodable, Sendable, Equatable, UserErrorsPayload {
    /// The changed customer.
    public let customer: Customer?
    /// Validation errors with Shopify's localized messages.
    public let userErrors: [UserError]
}

/// Changes the customer's first and last name (`customerUpdate`). The name is the only personal
/// detail the Customer Account API lets the customer change; the e-mail address is the login.
public struct CustomerUpdateMutation: GraphQLOperation {
    /// The operation variables.
    public struct Variables: Encodable, Sendable, Equatable {
        /// The new name.
        public let input: Input
    }

    /// The Customer Account API `CustomerUpdateInput`.
    public struct Input: Encodable, Sendable, Equatable {
        /// The first name.
        public let firstName: String
        /// The last name.
        public let lastName: String
    }

    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The payload.
        public let customerUpdate: CustomerUpdatePayload
    }

    /// `CustomerUpdate`.
    public static let operationName = "CustomerUpdate"
    /// A mutation.
    public static let kind = GraphQLOperationKind.mutation
    /// The operation and its fragments.
    public static let document = CustomerFragments.document(
        """
        mutation CustomerUpdate($input: CustomerUpdateInput!) {
          customerUpdate(input: $input) {
            customer {
              id
              displayName
              firstName
              lastName
              emailAddress {
                emailAddress
              }
              defaultAddress {
                ...CustomerAddressFields
              }
            }
            userErrors {
              field
              message
              code
            }
          }
        }
        """,
        fragments: [CustomerFragments.address]
    )

    /// The variables of this call.
    public let variables: Variables

    /// Creates the mutation.
    public init(firstName: String, lastName: String) {
        variables = Variables(input: Input(firstName: firstName, lastName: lastName))
    }
}
