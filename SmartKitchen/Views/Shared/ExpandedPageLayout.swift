import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Search Overlay Environment Key

private struct SearchOverlayKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: AnyView? = nil
}

extension EnvironmentValues {
    var searchOverlay: AnyView? {
        get { self[SearchOverlayKey.self] }
        set { self[SearchOverlayKey.self] = newValue }
    }
}

private struct SuspendAnimatedPageBackgroundKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue = false
}

extension EnvironmentValues {
    var suspendAnimatedPageBackground: Bool {
        get { self[SuspendAnimatedPageBackgroundKey.self] }
        set { self[SuspendAnimatedPageBackgroundKey.self] = newValue }
    }
}

/// True while the foreground-burst mitigation window is active. Views that
/// own heavy `@Query` subscribers should unmount them (after the initial
/// load) while this is `true` so the CloudKit remote-change burst doesn't
/// trigger dozens of main-thread fetches per change.
private struct SuspendActiveTabDataSubscriptionsKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue = false
}

extension EnvironmentValues {
    var suspendActiveTabDataSubscriptions: Bool {
        get { self[SuspendActiveTabDataSubscriptionsKey.self] }
        set { self[SuspendActiveTabDataSubscriptionsKey.self] = newValue }
    }
}

struct ContentPanelCutoutDescriptor {
    let bounds: Anchor<CGRect>
    let style: ContentPanelCutoutStyle
}

enum ContentPanelCutoutStyle {
    case nutritionCalories(text: String)
}

struct ContentPanelCutoutKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [ContentPanelCutoutDescriptor] = []

    static func reduce(value: inout [ContentPanelCutoutDescriptor], nextValue: () -> [ContentPanelCutoutDescriptor]) {
        value.append(contentsOf: nextValue())
    }
}

enum ExpandedPageHeaderMetrics {
    static let iosTitleHeight: CGFloat = 60
    static let iosInfoTopPadding: CGFloat = 4
    static let iosInfoBottomGap: CGFloat = 16
    static let iosEmptyInfoHeight: CGFloat = 0
    static let iosCompactInfoHeight: CGFloat = 44

    static func iosShaderHeight(infoHeight: CGFloat) -> CGFloat {
        iosInfoTopPadding + infoHeight + iosInfoBottomGap
    }

    static func iosTotalHeight(infoHeight: CGFloat) -> CGFloat {
        iosTitleHeight + iosShaderHeight(infoHeight: infoHeight)
    }
}

// MARK: - Expanded Page Layout

/// Layout with a fixed animated background, a floating header, and a
/// content area that manages its own scrolling.
/// The shader zone now hosts a UnifiedSearchBar that is revealed by
/// dragging down anywhere on the page or pressing the search button.
struct ExpandedPageLayout<Header: View, Content: View, InfoContent: View>: View {
    let pageTheme: PageTheme
    let header: (_ isInverted: Bool) -> Header
    let content: () -> Content
    let infoContent: () -> InfoContent
    let startsWithInfoCollapsed: Bool
    let backgroundOverride: AnyView?

    private var backgroundManager = BackgroundManager.shared

    @Environment(\.backgroundTheme) private var backgroundTheme
    @Environment(\.usesGlobalPageBackground) private var usesGlobalPageBackground
    @Environment(\.visiblePageTheme) private var visiblePageTheme
    @Environment(\.searchOverlay) private var searchOverlay
    @Environment(\.suspendAnimatedPageBackground) private var suspendAnimatedPageBackground
    @EnvironmentObject private var searchBarState: SearchBarState

    /// Use the animated background theme from environment if available, otherwise fall back to the page's own theme.
    private var effectiveBgTheme: PageTheme { backgroundTheme ?? pageTheme }

    private let headerHeight: CGFloat = ExpandedPageHeaderMetrics.iosTitleHeight
    private let cornerRadius: CGFloat = 24
    private let topMargin: CGFloat = 10
    private let leadingPanelInset: CGFloat = 8
    #if os(macOS)
    private let macHeaderTopInset: CGFloat = -14
    private let macHeaderHeight: CGFloat = 34
    private let macBottomInset: CGFloat = 8
    #endif
    private let bottomTabBarContentInset: CGFloat = 130


    // Background transition state
    @State private var backgroundFromTheme: PageTheme = .home
    @State private var backgroundToTheme: PageTheme = .home
    @State private var backgroundTransitionProgress: Double = 1.0

    // Drag-to-reveal state
    @State private var dragOffset: CGFloat = 0
    private let revealThreshold: CGFloat = 40

    private var shouldAnimateShaderBackground: Bool {
        #if os(macOS)
        true
        #else
        guard !suspendAnimatedPageBackground else { return false }
        guard !usesGlobalPageBackground else { return false }
        guard let visiblePageTheme else { return true }
        return visiblePageTheme == pageTheme
        #endif
    }

    private var trailingPanelInset: CGFloat {
        #if os(macOS)
        4
        #else
        leadingPanelInset
        #endif
    }

    #if os(macOS)
    private var macContainerTopGap: CGFloat {
        18
    }
    #endif

    init(
        pageTheme: PageTheme,
        startsWithInfoCollapsed: Bool = false,
        backgroundOverride: AnyView? = nil,
        @ViewBuilder header: @escaping (_ isInverted: Bool) -> Header,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder infoContent: @escaping () -> InfoContent
    ) {
        self.pageTheme = pageTheme
        self.startsWithInfoCollapsed = startsWithInfoCollapsed
        self.backgroundOverride = backgroundOverride
        self.header = header
        self.content = content
        self.infoContent = infoContent
    }



    var body: some View {
        #if os(macOS)
        ZStack(alignment: .top) {
            backgroundLayer
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                header(false)
                    .frame(height: macHeaderHeight)
                    .padding(.top, macHeaderTopInset)

                infoContent()
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 10)

                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(appPrimaryBackground)

                    VStack(spacing: 0) {
                        Color.clear.frame(height: topMargin)
                        content()
                        Spacer(minLength: 0)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .padding(.top, macContainerTopGap)
                .padding(.horizontal, 16)
                .padding(.bottom, macBottomInset)
            }
        }
        #else
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                // Fixed page background. Keep this inside the page even when the
                // app also keeps global backgrounds warm: TabView/NavigationStack
                // can draw an opaque host behind the tab content on iOS, so the
                // shader/header area must not depend on a background behind them.
                backgroundLayer
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // LAYOUT
                VStack(spacing: 0) {
                    // Fixed header (transparent, over shader)
                    header(false)
                        .frame(height: headerHeight)

                    // Shader zone: info content + search bar slot
                    shaderZone

                    // Content area
                    contentArea
                }
                .padding(.top, proxy.safeAreaInsets.top)
            }
            .ignoresSafeArea(edges: .top)
        }
        .onAppear {
            searchBarState.pageContext = pageTheme.searchContext
    }
    #endif
}

    // MARK: - Shader Zone (iOS)

    #if !os(macOS)
    @ViewBuilder
    private var shaderZone: some View {
        VStack(spacing: 0) {
            infoContent()
                .padding(.horizontal, 20)
                .padding(.top, ExpandedPageHeaderMetrics.iosInfoTopPadding)

            Spacer().frame(height: ExpandedPageHeaderMetrics.iosInfoBottomGap)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
    #endif

    // MARK: - Content Area (iOS)

    #if !os(macOS)
    private var contentArea: some View {
        ZStack(alignment: .top) {
            content()
                .padding(.top, topMargin)

            // Search results rendered inside the content panel
            if searchBarState.isVisible, let searchOverlay {
                searchOverlay
                    .padding(.top, topMargin)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: bottomTabBarContentInset)
        }
        .background(appPrimaryBackground)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: cornerRadius
            )
        )
        .ignoresSafeArea(edges: .bottom)
        .padding(.leading, leadingPanelInset)
        .padding(.trailing, trailingPanelInset)
        .overlayPreferenceValue(ContentPanelCutoutKey.self) { cutouts in
            GeometryReader { proxy in
                ForEach(Array(cutouts.enumerated()), id: \.offset) { _, cutout in
                    cutoutView(for: cutout, in: proxy)
                }
            }
            .allowsHitTesting(false)
        }
        .compositingGroup()
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: searchBarState.isVisible)
    }

    @ViewBuilder
    private func cutoutView(for cutout: ContentPanelCutoutDescriptor, in proxy: GeometryProxy) -> some View {
        let rect = proxy[cutout.bounds]

        switch cutout.style {
        case .nutritionCalories(let text):
            Text(text)
                .font(.custom("Bricolage Grotesque", size: 96, relativeTo: .largeTitle).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .blendMode(.destinationOut)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
    #endif

    // MARK: - Drag to Reveal Gesture

    private var dragToRevealGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { value in
                let dy = value.translation.height
                if searchBarState.isVisible {
                    if dy < 0 {
                        withAnimation(.interactiveSpring) {
                            dragOffset = dy
                        }
                    }
                } else {
                    if dy > 0 {
                        withAnimation(.interactiveSpring) {
                            dragOffset = dy
                        }
                    }
                }
            }
            .onEnded { _ in
                if searchBarState.isVisible {
                    if dragOffset <= -revealThreshold {
                        searchBarState.dismiss()
                    }
                } else {
                    if dragOffset >= revealThreshold {
                        searchBarState.reveal(mode: .idle)
                    }
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    dragOffset = 0
                }
            }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        if let backgroundOverride {
            backgroundOverride
        } else {
            ZStack {
                Color.black
                if backgroundTransitionProgress < 0.999 {
                    themedBackground(for: backgroundFromTheme)
                        .opacity(1.0 - backgroundTransitionProgress)
                }
                themedBackground(for: backgroundToTheme)
                    .opacity(backgroundTransitionProgress)
            }
            .onAppear {
                backgroundFromTheme = effectiveBgTheme
                backgroundToTheme = effectiveBgTheme
                backgroundTransitionProgress = 1.0
            }
            .onChange(of: effectiveBgTheme) { _, newTheme in
                guard newTheme != backgroundToTheme else { return }
                backgroundFromTheme = backgroundToTheme
                backgroundToTheme = newTheme
                #if os(macOS)
                backgroundTransitionProgress = 1.0
                #else
                backgroundTransitionProgress = 0.0
                withAnimation(.easeInOut(duration: 0.35)) {
                    backgroundTransitionProgress = 1.0
                }
                #endif
            }
        }
    }

    @ViewBuilder
    private func themedBackground(for theme: PageTheme) -> some View {
        ThemedBackgroundView(
            theme: theme,
            selection: backgroundManager.background(for: theme),
            progress: 1.0,
            animated: shouldAnimateShaderBackground
        )
    }
}

// MARK: - Deferred Tab Loading

struct DeferredTabPage<Loaded: View, Placeholder: View>: View {
    let tab: AppTab
    var delay: Duration = .milliseconds(320)
    @ViewBuilder var loaded: () -> Loaded
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.activeAppTab) private var activeAppTab
    @State private var isReady = false
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        #if os(iOS)
        Group {
            if isReady {
                loaded()
            } else {
                placeholder()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            updateReadiness(for: activeAppTab)
        }
        .onChange(of: activeAppTab) { _, newValue in
            updateReadiness(for: newValue)
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        #else
        loaded()
        #endif
    }

    #if os(iOS)
    private func updateReadiness(for activeTab: AppTab?) {
        guard activeTab == tab else {
            loadTask?.cancel()
            loadTask = nil
            isReady = false
            return
        }

        guard !isReady, loadTask == nil else { return }

        loadTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            isReady = true
            loadTask = nil
        }
    }
    #endif
}

struct PageSkeletonRows: View {
    var rowCount: Int = 9
    var showsCategoryBar = true

    var body: some View {
        VStack(spacing: 0) {
            if showsCategoryBar {
                SkeletonSegmentedBar()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }

            VStack(spacing: 0) {
                ForEach(0..<rowCount, id: \.self) { index in
                    SkeletonListRow(index: index)
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .skeletonShimmer()
        .allowsHitTesting(false)
    }
}

struct PageSkeletonGrid: View {
    var columns = 3
    var itemCount = 12
    var showsCategoryBar = true

    var body: some View {
        VStack(spacing: 0) {
            if showsCategoryBar {
                SkeletonSegmentedBar()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: columns), spacing: 1) {
                ForEach(0..<itemCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(skeletonBaseColor)
                        .aspectRatio(0.78, contentMode: .fit)
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 8) {
                                Capsule()
                                    .fill(skeletonHighlightColor)
                                    .frame(width: index.isMultiple(of: 2) ? 72 : 96, height: 12)
                                Capsule()
                                    .fill(skeletonHighlightColor.opacity(0.75))
                                    .frame(width: 48, height: 9)
                            }
                            .padding(12)
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .skeletonShimmer()
        .allowsHitTesting(false)
    }
}

struct PageSkeletonNotebooks: View {
    var columns = 2
    var itemCount = 8

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
            spacing: 12
        ) {
            ForEach(0..<itemCount, id: \.self) { index in
                SkeletonNotebookCard(index: index)
            }
        }
        .skeletonShimmer()
        .allowsHitTesting(false)
    }
}

private struct SkeletonNotebookCard: View {
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(skeletonBaseColor)
                .frame(height: 118)
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(skeletonHighlightColor.opacity(0.86))
                        .frame(width: 42, height: 30)
                        .padding(10)
                }

            VStack(alignment: .leading, spacing: 8) {
                Capsule()
                    .fill(skeletonBaseColor)
                    .frame(width: index.isMultiple(of: 2) ? 104 : 132, height: 15)

                HStack(spacing: 12) {
                    Capsule()
                        .fill(skeletonBaseColor.opacity(0.72))
                        .frame(width: 54, height: 11)
                    Capsule()
                        .fill(skeletonBaseColor.opacity(0.72))
                        .frame(width: 64, height: 11)
                }
            }
        }
        .frame(height: 168, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(skeletonBaseColor.opacity(0.55), in: .rect(cornerRadius: 18))
    }
}

struct NutritionPageSkeleton: View {
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(skeletonBaseColor)
                    .frame(height: 176)

                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(skeletonBaseColor)
                        .frame(height: 108)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(skeletonBaseColor)
                        .frame(height: 108)
                }

                ForEach(0..<5, id: \.self) { index in
                    SkeletonListRow(index: index)
                        .background(skeletonBaseColor.opacity(0.55), in: .rect(cornerRadius: 16))
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollIndicators(.hidden)
        .skeletonShimmer()
        .clipped()
        .allowsHitTesting(false)
    }
}

struct NutritionInfoSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.24))
                .frame(height: 28)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.18))
                .frame(width: 92, height: 32)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: ExpandedPageHeaderMetrics.iosCompactInfoHeight)
        .skeletonShimmer()
        .clipped()
        .allowsHitTesting(false)
    }
}

private struct SkeletonSegmentedBar: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(index == 0 ? skeletonHighlightColor : skeletonBaseColor)
                    .frame(height: 34)
            }
        }
        .padding(4)
        .background(skeletonBaseColor.opacity(0.6), in: .rect(cornerRadius: 12))
    }
}

private struct SkeletonListRow: View {
    let index: Int

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(skeletonBaseColor)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 8) {
                Capsule()
                    .fill(skeletonBaseColor)
                    .frame(width: index.isMultiple(of: 3) ? 136 : 190, height: 14)
                Capsule()
                    .fill(skeletonBaseColor.opacity(0.72))
                    .frame(width: index.isMultiple(of: 2) ? 80 : 112, height: 10)
            }

            Spacer()

            Circle()
                .stroke(skeletonBaseColor, lineWidth: 4)
                .frame(width: 42, height: 42)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(skeletonBaseColor.opacity(0.55))
                .frame(height: 1)
                .padding(.leading, 74)
                .padding(.trailing, 16)
        }
    }
}

private struct SkeletonShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.34), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .rotationEffect(.degrees(18))
                    .frame(width: geometry.size.width * 0.55, height: geometry.size.height * 1.6)
                    .offset(x: geometry.size.width * phase, y: -geometry.size.height * 0.25)
                    .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
            }
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    phase = 2.1
                }
            }
    }
}

private extension View {
    func skeletonShimmer() -> some View {
        modifier(SkeletonShimmerModifier())
    }
}

private var skeletonBaseColor: Color {
    #if os(iOS)
    Color(.systemGray5)
    #else
    Color.secondary.opacity(0.15)
    #endif
}

private var skeletonHighlightColor: Color {
    #if os(iOS)
    Color(.systemBackground).opacity(0.92)
    #else
    Color.primary.opacity(0.12)
    #endif
}
