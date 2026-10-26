import CommerceUI
import DesignSystem
import ShopifyKit
import SwiftUI

// MARK: - HomeCategoryShowcase

/// "Unsere Kategorien", as the brand strip of fashion retail apps: a row of category tiles
/// above a large panel in the store color with the products of the chosen category in large
/// portrait cards. The last tile leads to the whole range in the Shop tab.
///
/// The showcase moves on by itself, as in the About You app: the chosen tile fills with a
/// lighter tone over ``HomeShowcaseCycle/dwell``, then the next category takes over with a soft
/// cross-fade and the row of tiles glides along. It holds still while it is off screen or the
/// app is not active, with VoiceOver, Switch Control or Reduce Motion, and as soon as the
/// customer takes over by tapping a tile or scrolling the tiles or the products. Once it has
/// been off screen it moves on again from the category shown.
///
/// The panels of all categories lie on top of each other with only the chosen one visible, so
/// the panel keeps its height from category to category and a switch shows products that are
/// already loaded. A category whose collection turns out empty gets no tile.
struct HomeCategoryShowcase: View {
    let categories: [HomeCategory]
    /// Whether the showcase moves on by itself (off in UI tests, for a still screen).
    let cyclesAutomatically: Bool
    let state: @MainActor (HomeCategory) -> LoadState<[ProductSummary]>
    let retry: @MainActor (HomeCategory) async -> Void
    let onOpen: @MainActor (HomeCategory) -> Void
    let onBrowseAll: @MainActor () -> Void
    let onSelect: @MainActor (ProductSummary) -> Void

    @State private var selectedHandle: String?
    /// Whether the showcase belongs to the screen on display (not behind a pushed screen or in
    /// another tab).
    @State private var isOnScreen = false
    /// Whether at least half of the showcase is scrolled into view. Tracked from iOS 18; on
    /// earlier versions it stays `true`.
    @State private var isInView = true
    /// Whether the customer took over since the showcase was last off screen.
    @State private var isHeldByCustomer = false
    /// The customer's taps on tiles, for the selection haptic.
    @State private var tapCount = 0

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var isSwitchControlEnabled

    var body: some View {
        let shown = shownCategories
        if let selected = shown.first(where: { $0.handle == selectedHandle }) ?? shown.first {
            let isCycling = cycles(categoryCount: shown.count)
            VStack(alignment: .leading, spacing: KXSpacing.m) {
                KXSectionHeader(
                    String(localized: "home.showcase.title", bundle: .module),
                    eyebrow: String(localized: "home.showcase.eyebrow", bundle: .module)
                )
                .padding(.horizontal, KXSpacing.gutter)
                tiles(shown, selected: selected, isCycling: isCycling)
                panels(shown, selected: selected)
                    .padding(.horizontal, KXSpacing.gutter)
            }
            .task(id: HomeShowcaseCycle.Step(handle: selected.handle, isCycling: isCycling)) {
                if isCycling {
                    await moveOn(from: selected.handle, in: shown)
                }
            }
            .onAppear {
                isOnScreen = true
            }
            .onDisappear {
                isOnScreen = false
                isHeldByCustomer = false
            }
            .modifier(HomeScrollVisibility(isInView: $isInView))
            .onChange(of: isInView) { _, isInView in
                if !isInView {
                    isHeldByCustomer = false
                }
            }
            .sensoryFeedback(.selection, trigger: tapCount)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.showcase")
        }
    }

    // MARK: State

    /// The categories with a tile: all but those whose collection turned out empty.
    private var shownCategories: [HomeCategory] {
        categories.filter { category in
            if case .empty = state(category) { false } else { true }
        }
    }

    /// Whether the showcase moves on by itself right now.
    private func cycles(categoryCount: Int) -> Bool {
        HomeShowcaseCycle.Conditions(
            isEnabled: cyclesAutomatically,
            categoryCount: categoryCount,
            isVisible: isOnScreen && isInView && scenePhase == .active,
            isHeldByCustomer: isHeldByCustomer,
            prefersStillContent: reduceMotion || isVoiceOverEnabled || isSwitchControlEnabled
        )
        .cycles
    }

    /// Waits ``HomeShowcaseCycle/dwell`` on the category `handle`, then shows the next one.
    /// A change of the category or of the conditions cancels the wait.
    private func moveOn(from handle: String, in shown: [HomeCategory]) async {
        try? await Task.sleep(for: HomeShowcaseCycle.dwell)
        guard !Task.isCancelled, let next = HomeShowcaseCycle.handle(after: handle, in: shown.map(\.handle)) else {
            return
        }
        withAnimation(KXMotion.animation(.swap, reduceMotion: reduceMotion)) {
            selectedHandle = next
        }
    }

    /// Shows `category` after a tap on its tile; the showcase then holds still.
    private func choose(_ category: HomeCategory) {
        isHeldByCustomer = true
        tapCount += 1
        withAnimation(KXMotion.animation(.swap, reduceMotion: reduceMotion)) {
            selectedHandle = category.handle
        }
    }

    // MARK: Parts

    private func tiles(_ shown: [HomeCategory], selected: HomeCategory, isCycling: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: KXSpacing.xs) {
                    ForEach(shown) { category in
                        let isChosen = category == selected
                        HomeCategoryTile(
                            title: category.title.resolved,
                            systemImage: category.systemImage,
                            isSelected: isChosen,
                            showsProgress: isChosen && isCycling
                        ) {
                            choose(category)
                        }
                        .id(category.handle)
                        .accessibilityIdentifier("home.category.\(category.handle)")
                    }
                    HomeCategoryTile(
                        title: String(localized: "home.showcase.all", bundle: .module),
                        systemImage: "square.grid.2x2",
                        isSelected: false,
                        action: onBrowseAll
                    )
                    .accessibilityIdentifier("home.categories.all")
                }
                .padding(.horizontal, KXSpacing.gutter)
            }
            // The chosen tile's shadow reaches below the row.
            .scrollClipDisabled()
            .modifier(HomeCustomerScroll { isHeldByCustomer = true })
            .onChange(of: selected.handle) { _, handle in
                withAnimation(KXMotion.animation(.swap, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(handle, anchor: .center)
                }
            }
        }
    }

    private func panels(_ shown: [HomeCategory], selected: HomeCategory) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(shown) { category in
                let isShown = category == selected
                HomePanelContent(
                    eyebrow: category.eyebrow?.resolved,
                    title: category.title.resolved,
                    isSale: false,
                    state: state(category),
                    cardSize: .large,
                    retry: { await retry(category) },
                    onShowAll: { onOpen(category) },
                    onSelect: onSelect
                )
                .modifier(HomeCustomerScroll { isHeldByCustomer = true })
                .kxSkeletonShimmer(isShown)
                .opacity(isShown ? 1 : 0)
                .blur(radius: isShown || reduceMotion ? 0 : KXMotion.swapBlurRadius)
                .allowsHitTesting(isShown)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.panel.\(category.handle)")
                .accessibilityHidden(!isShown)
            }
        }
        .homeStorePanel()
    }
}

// MARK: - HomeShowcaseCycle

/// When the category showcase moves on by itself, and to which category.
enum HomeShowcaseCycle {
    /// How long a category stays before the next one takes over.
    static let dwell = KXMotion.cycleDwell

    /// One wait of the showcase: the category shown and whether it moves on. A new value
    /// starts the wait again.
    struct Step: Hashable {
        let handle: String
        let isCycling: Bool
    }

    /// What decides whether the showcase moves on by itself.
    struct Conditions: Hashable {
        /// Whether moving on by itself is allowed at all (UI tests turn it off).
        var isEnabled: Bool
        /// The number of categories with a tile; a single one never moves on.
        var categoryCount: Int
        /// Whether the showcase is on screen in the active app.
        var isVisible: Bool
        /// Whether the customer took over by tapping a tile or scrolling.
        var isHeldByCustomer: Bool
        /// Whether VoiceOver, Switch Control or Reduce Motion asks for content that holds still.
        var prefersStillContent: Bool

        /// Whether the showcase moves on by itself.
        var cycles: Bool {
            isEnabled && categoryCount > 1 && isVisible && !isHeldByCustomer && !prefersStillContent
        }
    }

    /// The handle after `handle` in `handles`, and the first one after the last. The first one
    /// when `handle` is not among them; `nil` without handles.
    static func handle(after handle: String, in handles: [String]) -> String? {
        guard let index = handles.firstIndex(of: handle) else {
            return handles.first
        }
        return handles[(index + 1) % handles.count]
    }
}

// MARK: - HomeCategoryTile

/// One category tile: the symbol above the short name. The chosen tile is filled in the store
/// color with light text and lifted by a soft shadow; while the showcase waits to move on it
/// fills with a lighter tone from the leading edge.
struct HomeCategoryTile: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    /// Whether the chosen tile shows the time until the showcase moves on.
    var showsProgress = false
    let action: @MainActor () -> Void

    @ScaledMetric(relativeTo: .caption) private var scaledWidth: CGFloat = 92
    @ScaledMetric(relativeTo: .caption) private var scaledHeight: CGFloat = 72
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: KXRadius.small, style: .continuous)
        Button {
            action()
        } label: {
            VStack(spacing: KXSpacing.xxs) {
                Image(systemName: systemImage)
                    .kxFont(.title3)
                Text(title)
                    .fontWeight(.medium)
                    .kxFont(.caption)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(KXColor.textPrimary)
            .padding(KXSpacing.xxs)
            .frame(width: min(scaledWidth, 150), height: min(scaledHeight, 120))
            .background {
                if isSelected {
                    ZStack {
                        KXColor.storePanel
                        if showsProgress {
                            HomeShowcaseProgress()
                        }
                    }
                    .clipShape(shape)
                    .shadow(color: KXColor.scrim.opacity(0.2), radius: KXSpacing.xs, y: KXSpacing.xxs)
                } else {
                    shape.fill(KXColor.background)
                }
            }
            .overlay {
                if !isSelected {
                    shape.strokeBorder(KXColor.divider, lineWidth: KXBorder.regular)
                }
            }
            .contentShape(shape)
            // Light text on the store color.
            .environment(\.colorScheme, isSelected ? .dark : colorScheme)
        }
        .buttonStyle(.kxPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - HomeShowcaseProgress

/// The lifted store color that fills the chosen tile from the leading edge over
/// ``HomeShowcaseCycle/dwell``. Each wait of the showcase starts a new, empty one.
private struct HomeShowcaseProgress: View {
    @State private var isFull = false

    var body: some View {
        GeometryReader { proxy in
            KXColor.storePanelLifted
                .offset(x: isFull ? 0 : -proxy.size.width)
        }
        .onAppear {
            withAnimation(KXMotion.cycleProgress) {
                isFull = true
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Modifiers

/// Keeps `isInView` up to date with whether at least half of the view is scrolled into view,
/// from iOS 18. Earlier versions leave it as it is.
private struct HomeScrollVisibility: ViewModifier {
    @Binding var isInView: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollVisibilityChange(threshold: 0.5) { isVisible in
                isInView = isVisible
            }
        } else {
            content
        }
    }
}

/// Calls `action` as soon as the customer scrolls the first scroll view inside the view. Before
/// iOS 18, which reports no scroll phases, a sideways drag counts.
private struct HomeCustomerScroll: ViewModifier {
    let action: @MainActor () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .interacting {
                    action()
                }
            }
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: KXSpacing.xs).onChanged { drag in
                    if abs(drag.translation.width) > abs(drag.translation.height) {
                        action()
                    }
                }
            )
        }
    }
}
