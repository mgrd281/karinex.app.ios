import Foundation

// MARK: - LoadState

/// The state of a screen or section that loads content: the single source for skeletons,
/// content, empty states and errors. Render it with ``AsyncContentView``.
///
/// ```swift
/// @MainActor @Observable final class CollectionViewModel {
///     private(set) var state: LoadState<CollectionPage> = .idle
///
///     func load() async {
///         if state.value == nil { state = .loading }
///         do {
///             let page = try await repository.collection(handle: handle, first: 24)
///             state = LoadState(page, isEmpty: { $0.products.isEmpty })
///         } catch {
///             if let failure = UserFacingError(error) { state = .failed(failure) }
///         }
///     }
/// }
/// ```
public enum LoadState<Value> {
    /// Nothing requested yet.
    case idle
    /// A request is running and there is no content to show yet.
    case loading
    /// The content.
    case loaded(Value)
    /// The request succeeded but returned nothing (an empty list, a missing product).
    case empty
    /// The request failed.
    case failed(UserFacingError)

    /// Creates `.loaded(value)`, or `.empty` when `value` is `nil` or `isEmpty(value)` is `true`.
    public init(_ value: Value?, isEmpty: (Value) -> Bool = { _ in false }) {
        if let value, !isEmpty(value) {
            self = .loaded(value)
        } else {
            self = .empty
        }
    }

    /// The loaded content, if any.
    public var value: Value? {
        if case let .loaded(value) = self {
            return value
        }
        return nil
    }

    /// The failure, if the state is ``failed(_:)``.
    public var error: UserFacingError? {
        if case let .failed(error) = self {
            return error
        }
        return nil
    }

    /// Whether the state is ``idle`` or ``loading``, i.e. a skeleton is shown.
    public var isLoading: Bool {
        switch self {
        case .idle, .loading:
            true
        case .loaded, .empty, .failed:
            false
        }
    }

    /// Transforms the loaded content, keeping every other state.
    public func map<NewValue>(_ transform: (Value) -> NewValue) -> LoadState<NewValue> {
        switch self {
        case .idle:
            .idle
        case .loading:
            .loading
        case let .loaded(value):
            .loaded(transform(value))
        case .empty:
            .empty
        case let .failed(error):
            .failed(error)
        }
    }
}

extension LoadState: Sendable where Value: Sendable {}
extension LoadState: Equatable where Value: Equatable {}
extension LoadState: Hashable where Value: Hashable {}

extension LoadState where Value: Collection {
    /// Creates `.loaded(collection)`, or `.empty` when the collection is empty.
    public init(collection: Value) {
        self.init(collection, isEmpty: \.isEmpty)
    }
}
