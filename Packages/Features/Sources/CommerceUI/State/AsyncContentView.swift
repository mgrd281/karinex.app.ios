import DesignSystem
import SwiftUI

// MARK: - AsyncContentEmptyState

/// What ``AsyncContentView`` shows for ``LoadState/empty``: an SF Symbol, a title, a message
/// and an optional action, all already localized by the caller.
public struct AsyncContentEmptyState {
    /// The SF Symbol on the light grey disc.
    public let systemImage: String
    /// The bold title.
    public let title: String
    /// The explanation.
    public let message: String
    /// The label of the optional action button.
    public let actionTitle: String?
    /// The optional action, e.g. switching to the Shop tab.
    public let action: (@MainActor () -> Void)?

    /// Creates an empty state.
    ///
    /// - Parameters:
    ///   - systemImage: The SF Symbol.
    ///   - title: The localized title.
    ///   - message: The localized message.
    ///   - actionTitle: The localized label of the action; the button is shown only with an action.
    ///   - action: The action.
    public init(
        systemImage: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (@MainActor () -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    /// The neutral default: "Nichts gefunden" with a short explanation.
    @MainActor public static var standard: AsyncContentEmptyState {
        AsyncContentEmptyState(
            systemImage: "tray",
            title: String(localized: "commerce.empty.title", bundle: .module),
            message: String(localized: "commerce.empty.message", bundle: .module)
        )
    }
}

// MARK: - AsyncContentView

/// Renders a ``LoadState``: the placeholder (a skeleton) while idle or loading, the content
/// when loaded, a ``KXEmptyState`` when empty, and ``AsyncErrorView`` with "Erneut versuchen"
/// when the request failed (with an offline message when the device has no connection).
///
/// Every list and detail screen uses it, so loading, empty and error states look and behave
/// the same everywhere:
///
/// ```swift
/// AsyncContentView(model.state, retry: { await model.load() }) { page in
///     CollectionGrid(page: page)
/// } placeholder: {
///     CollectionGridSkeleton()
/// }
/// ```
///
/// The state change is animated with the standard KARINEX fade (instant with Reduce Motion).
public struct AsyncContentView<Value, Content: View, Placeholder: View>: View {
    private let state: LoadState<Value>
    private let emptyState: AsyncContentEmptyState?
    private let retry: (@MainActor () async -> Void)?
    private let content: (Value) -> Content
    private let placeholder: Placeholder

    /// Creates the view.
    ///
    /// - Parameters:
    ///   - state: The state to render.
    ///   - empty: The empty state. `nil` uses ``AsyncContentEmptyState/standard``.
    ///   - retry: Called by "Erneut versuchen" in the error state. Without it no button is shown.
    ///   - content: Builds the content for a loaded value.
    ///   - placeholder: The skeleton shown while idle or loading.
    public init(
        _ state: LoadState<Value>,
        empty: AsyncContentEmptyState? = nil,
        retry: (@MainActor () async -> Void)? = nil,
        @ViewBuilder content: @escaping (Value) -> Content,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.state = state
        emptyState = empty
        self.retry = retry
        self.content = content
        self.placeholder = placeholder()
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        ZStack {
            switch state {
            case .idle, .loading:
                placeholder
                    .accessibilityIdentifier("state.loading")
                    .transition(.opacity)
            case let .loaded(value):
                content(value)
                    .transition(.opacity)
            case .empty:
                emptyView
                    .accessibilityIdentifier("state.empty")
                    .transition(.opacity)
            case let .failed(error):
                AsyncErrorView(error, retry: retry)
                    .transition(.opacity)
            }
        }
        .animation(KXMotion.animation(.fade, reduceMotion: reduceMotion), value: phase)
    }

    private var emptyView: some View {
        let empty = emptyState ?? .standard
        return ScrollView {
            KXEmptyState(
                systemImage: empty.systemImage,
                title: empty.title,
                message: empty.message,
                actionTitle: empty.action == nil ? nil : empty.actionTitle,
                action: empty.action.map { action in { action() } }
            )
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// The case of `state` without its payload, so changes animate without `Value: Equatable`.
    private var phase: Int {
        switch state {
        case .idle, .loading:
            0
        case .loaded:
            1
        case .empty:
            2
        case .failed:
            3
        }
    }
}

extension AsyncContentView where Placeholder == AsyncContentSkeleton {
    /// Creates the view with the generic ``AsyncContentSkeleton`` as placeholder.
    ///
    /// - Parameters:
    ///   - state: The state to render.
    ///   - empty: The empty state. `nil` uses ``AsyncContentEmptyState/standard``.
    ///   - retry: Called by "Erneut versuchen" in the error state.
    ///   - content: Builds the content for a loaded value.
    public init(
        _ state: LoadState<Value>,
        empty: AsyncContentEmptyState? = nil,
        retry: (@MainActor () async -> Void)? = nil,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.init(state, empty: empty, retry: retry, content: content) {
            AsyncContentSkeleton()
        }
    }
}

// MARK: - AsyncErrorView

/// The error state of ``AsyncContentView``, also usable on its own (for example inside a
/// section): symbol, title and message of a ``UserFacingError`` and, when the error is
/// retryable and a `retry` action is given, an "Erneut versuchen" button.
public struct AsyncErrorView: View {
    private let error: UserFacingError
    private let retry: (@MainActor () async -> Void)?

    @State private var isRetrying = false

    /// Creates the error view.
    ///
    /// - Parameters:
    ///   - error: The failure to explain.
    ///   - retry: The retry action. The button is hidden when `nil` or when the error is not
    ///     retryable.
    public init(_ error: UserFacingError, retry: (@MainActor () async -> Void)? = nil) {
        self.error = error
        self.retry = retry
    }

    public var body: some View {
        ScrollView {
            KXEmptyState(
                systemImage: error.systemImage,
                title: error.title,
                message: error.message,
                actionTitle: retryAction == nil ? nil : UserFacingError.retryTitle,
                action: retryAction
            )
            .disabled(isRetrying)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier(error.kind == .offline ? "state.offline" : "state.error")
    }

    private var retryAction: (() -> Void)? {
        guard error.isRetryable, let retry else { return nil }
        return {
            guard !isRetrying else { return }
            isRetrying = true
            Task {
                await retry()
                isRetrying = false
            }
        }
    }
}

// MARK: - AsyncContentSkeleton

/// A neutral loading placeholder: a large block and a few text lines with the KARINEX shimmer.
/// Screens with a known layout pass their own skeleton to ``AsyncContentView`` instead.
public struct AsyncContentSkeleton: View {
    /// Creates the skeleton.
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: KXSpacing.m) {
            KXSkeleton(cornerRadius: KXRadius.card)
                .aspectRatio(16 / 9, contentMode: .fit)
            KXSkeleton()
                .frame(height: KXSpacing.l)
                .padding(.trailing, KXSpacing.xxl)
            ForEach(0..<3, id: \.self) { _ in
                KXSkeleton()
                    .frame(height: KXSpacing.s)
            }
        }
        .padding(KXSpacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("commerce.loading", bundle: .module))
    }
}

// MARK: - Previews

private enum AsyncContentPreviewSample {
    static let title = "Microsoft Office 2024 Professional Plus Download kaufen"
}

#Preview("AsyncContentView, states") {
    TabView {
        AsyncContentView(LoadState<String>.loading) { Text($0) }
            .tabItem { Text(verbatim: "loading") }
        AsyncContentView(LoadState.loaded(AsyncContentPreviewSample.title)) { title in
            Text(title).kxFont(.title2).padding(KXSpacing.gutter)
        }
        .tabItem { Text(verbatim: "loaded") }
        AsyncContentView(LoadState<String>.empty) { Text($0) }
            .tabItem { Text(verbatim: "empty") }
        AsyncContentView(LoadState<String>.failed(UserFacingError(kind: .offline)), retry: {}, content: { Text($0) })
            .tabItem { Text(verbatim: "offline") }
    }
    .kxScreenBackground()
}

#Preview("AsyncErrorView, dark") {
    AsyncErrorView(UserFacingError(kind: .server), retry: {})
        .kxScreenBackground()
        .preferredColorScheme(.dark)
}

#Preview("AsyncErrorView, accessibility size") {
    AsyncErrorView(UserFacingError(kind: .timeout), retry: {})
        .kxScreenBackground()
        .dynamicTypeSize(.accessibility2)
}
