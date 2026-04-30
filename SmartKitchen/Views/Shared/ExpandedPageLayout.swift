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

    private var backgroundManager = BackgroundManager.shared

    @Environment(\.backgroundTheme) private var backgroundTheme
    @Environment(\.usesGlobalPageBackground) private var usesGlobalPageBackground
    @Environment(\.visiblePageTheme) private var visiblePageTheme
    @Environment(\.searchOverlay) private var searchOverlay
    @EnvironmentObject private var searchBarState: SearchBarState

    /// Use the animated background theme from environment if available, otherwise fall back to the page's own theme.
    private var effectiveBgTheme: PageTheme { backgroundTheme ?? pageTheme }

    private let headerHeight: CGFloat = 60
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
        @ViewBuilder header: @escaping (_ isInverted: Bool) -> Header,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder infoContent: @escaping () -> InfoContent
    ) {
        self.pageTheme = pageTheme
        self.startsWithInfoCollapsed = startsWithInfoCollapsed
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
        ZStack(alignment: .top) {
            // FIXED BACKGROUND
            if !usesGlobalPageBackground {
                backgroundLayer
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

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
                .padding(.top, 4)

            Spacer().frame(height: 16)
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
        .overlayPreferenceValue(ContentPanelCutoutKey.self) { cutouts in
            GeometryReader { proxy in
                ZStack {
                    ForEach(Array(cutouts.enumerated()), id: \.offset) { _, cutout in
                        cutoutView(for: cutout, in: proxy)
                    }
                }
            }
        }
        .compositingGroup()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
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
