import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Observable Scroll State (avoids AttributeGraph cycles)

/// Holds scroll offset in an @Observable class so that only child views
/// that *read* the offset re-evaluate — the parent view (which contains
/// the GeometryReader that *writes* the offset) never re-evaluates,
/// breaking the read → write → re-evaluate → read cycle.
@Observable
private final class _ExpandedScrollState {
    var scrollOffset: CGFloat = 0
    var isRefreshing: Bool = false
    var safeAreaTop: CGFloat = 0
    @ObservationIgnored var previousOffset: CGFloat = 0
    @ObservationIgnored var isRefreshingInternal: Bool = false
}

// MARK: - Expanded Page Layout

/// Layout where a single ScrollView controls content movement.
/// The animated background stays fixed, and the main content area scrolls over it.
struct ExpandedPageLayout<Header: View, Content: View, InfoContent: View>: View {
    let pageTheme: PageTheme
    let header: (_ isInverted: Bool) -> Header
    let content: () -> Content
    let infoContent: () -> InfoContent
    let startsWithInfoCollapsed: Bool
    var onRefresh: (() async -> Void)? = nil

    private var backgroundManager = BackgroundManager.shared

    private let infoAreaHeight: CGFloat = 100
    private let headerHeight: CGFloat = 60
    private let cornerRadius: CGFloat = 24
    private let topMargin: CGFloat = 10
    private let refreshThreshold: CGFloat = 80
    private let leadingPanelInset: CGFloat = 8

    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @State private var scrollState = _ExpandedScrollState()
    @State private var viewHeight: CGFloat = 800

    private var totalRevealHeight: CGFloat {
        headerHeight + infoAreaHeight
    }

    private var initialTopSpacerHeight: CGFloat {
        startsWithInfoCollapsed ? headerHeight : totalRevealHeight
    }

    private var trailingPanelInset: CGFloat {
        #if os(macOS)
        4
        #else
        leadingPanelInset
        #endif
    }

    init(
        pageTheme: PageTheme,
        startsWithInfoCollapsed: Bool = false,
        @ViewBuilder header: @escaping (_ isInverted: Bool) -> Header,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder infoContent: @escaping () -> InfoContent,
        onRefresh: (() async -> Void)? = nil
    ) {
        self.pageTheme = pageTheme
        self.startsWithInfoCollapsed = startsWithInfoCollapsed
        self.header = header
        self.content = content
        self.infoContent = infoContent
        self.onRefresh = onRefresh
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 1. FIXED BACKGROUND
            #if !os(macOS)
            backgroundLayer
                .ignoresSafeArea()
                .allowsHitTesting(false) // Previne interações com o shader
            #endif

            // 2. BOTTOM FILL (prevents shader from showing on bottom overscroll)
            VStack(spacing: 0) {
                Spacer()
                Color(.systemBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .padding(.leading, leadingPanelInset)
                    .padding(.trailing, trailingPanelInset)
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .allowsHitTesting(false)
            .zIndex(1)

            // 3. INFO AREA (behind scroll)
            _InfoAreaLayer(
                scrollState: scrollState,
                headerHeight: headerHeight,
                infoAreaHeight: infoAreaHeight,
                infoAreaView: buildInfoArea()
            )
            .zIndex(1.5)

            // 4. SCROLL CONTENT
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: initialTopSpacerHeight)
                            .allowsHitTesting(false)
                            .id("expandedScrollTop")

                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: topMargin)
                            content()
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        .frame(minHeight: max(0, viewHeight - headerHeight))
                        .background(Color(.systemBackground))
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: cornerRadius,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: cornerRadius
                            )
                        )
                    }
                    .background(
                        GeometryReader { scrollGeo in
                            Color.clear
                                .preference(
                                    key: ExpandedScrollOffsetKey.self,
                                    value: -scrollGeo.frame(in: .named("expanded_scroll")).minY
                                )
                        }
                    )
                }
                .padding(.leading, leadingPanelInset)
                .padding(.trailing, trailingPanelInset)
                .scrollIndicators(.hidden)
                #if os(macOS)
                .background(_OverlayScrollerConfigurator())
                #endif
                .coordinateSpace(name: "expanded_scroll")
                .onPreferenceChange(ExpandedScrollOffsetKey.self) { newOffset in
                    handleScrollChange(newOffset)
                }
                .onChange(of: scrollToTopTrigger) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        scrollProxy.scrollTo("expandedScrollTop", anchor: .top)
                    }
                }
            }
            .zIndex(2)

            // 5. PULL INDICATOR (reads safeAreaTop from scrollState)
            _PullIndicatorLayer(
                scrollState: scrollState,
                refreshThreshold: refreshThreshold
            )
            .zIndex(3)

            // 6. FLOATING TOP HEADER (on top of scroll to capture taps)
            _FloatingTopHeaderLayer(
                scrollState: scrollState,
                headerHeight: headerHeight,
                infoAreaHeight: infoAreaHeight,
                headerView: header(false)
            )
            .zIndex(4)

            // 7. INVERTED HEADER (reads safeAreaTop from scrollState)
            _InvertedHeaderLayer(
                scrollState: scrollState,
                headerHeight: headerHeight,
                infoAreaHeight: infoAreaHeight,
                headerView: header(true)
            )
            .zIndex(10)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { newHeight in
            viewHeight = newHeight
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.top }) { newTop in
            scrollState.safeAreaTop = newTop
        }
    }

    // MARK: - Scroll Handler (closure — no body dependency)

    private func handleScrollChange(_ newOffset: CGFloat) {
        let oldOffset = scrollState.previousOffset
        scrollState.previousOffset = newOffset

        // Only notify observers when the offset meaningfully changes.
        // Prevents redundant @Observable notifications and breaks the
        // preference → write → re-render → preference cycle.
        guard abs(oldOffset - newOffset) > 0.1 else { return }
        scrollState.scrollOffset = newOffset

        // Pull-to-refresh using non-observed backing flag
        guard let onRefresh, !scrollState.isRefreshingInternal else { return }
        let oldPull = max(0, -oldOffset)
        let newPull = max(0, -newOffset)
        if oldPull >= refreshThreshold && newPull < oldPull {
            scrollState.isRefreshingInternal = true
            scrollState.isRefreshing = true
            HapticManager.impact(style: .medium)
            Task {
                await onRefresh()
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        scrollState.isRefreshingInternal = false
                        scrollState.isRefreshing = false
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private func buildInfoArea() -> some View {
        VStack(spacing: 0) {
            infoContent()
                .padding(.horizontal, 20)
                .padding(.top, 12)

            Spacer()

            Image(systemName: "chevron.compact.up")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        let selection = backgroundManager.background(for: pageTheme)

        switch selection.type {
        case .texturedGradient:
            if let preset = selection.texturedPreset {
                TexturedGradientView(preset: preset, progress: 1.0)
            } else {
                originalBackground
            }
        case .original:
            originalBackground
        case .waves:
            WavesShaderView(progress: 1.0)
        }
    }

    @ViewBuilder
    private var originalBackground: some View {
        switch pageTheme {
        case .home:
            NebulaShaderView(
                theme: .home,
                progress: 1.0
            )
        case .lists:
            NebulaShaderView(
                theme: .lists,
                progress: 1.0
            )
        case .recipes:
            NebulaShaderView(
                theme: .recipes,
                progress: 1.0
            )
        case .nutrients:
            NebulaShaderView(
                theme: .nutrients,
                progress: 1.0
            )
        }
    }


}

// MARK: - Overlay Child Views (read scrollState — only THEY re-render)

/// Info area that sits behind the scroll content.
private struct _InfoAreaLayer<I: View>: View {
    let scrollState: _ExpandedScrollState
    let headerHeight: CGFloat
    let infoAreaHeight: CGFloat
    let infoAreaView: I

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: headerHeight)

            infoAreaView
                .frame(height: infoAreaHeight)
                .opacity(max(0.0, 1.0 - (scrollState.scrollOffset / (infoAreaHeight * 0.5))))
        }
    }
}

/// Floating header on top of the scroll content to ensure taps are caught.
private struct _FloatingTopHeaderLayer<H: View>: View {
    let scrollState: _ExpandedScrollState
    let headerHeight: CGFloat
    let infoAreaHeight: CGFloat
    let headerView: H

    private var headerCoverProgress: CGFloat {
        let p = (scrollState.scrollOffset - infoAreaHeight) / headerHeight
        return min(max(p, 0), 1)
    }

    var body: some View {
        headerView
            .frame(height: headerHeight)
            .opacity(1 - headerCoverProgress)
            .allowsHitTesting(headerCoverProgress < 0.5)
    }
}

/// Pull-to-refresh indicator shown when pulling past the top.
private struct _PullIndicatorLayer: View {
    let scrollState: _ExpandedScrollState
    let refreshThreshold: CGFloat

    private var pullProgress: CGFloat {
        let pull = max(0, -scrollState.scrollOffset)
        guard pull > 0 else { return 0 }
        return min(pull / refreshThreshold, 1.0)
    }

    var body: some View {
        VStack {
            if scrollState.isRefreshing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
            } else {
                Image(systemName: "arrow.down")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(pullProgress >= 1.0 ? 180 : 0))
                    .animation(.easeInOut(duration: 0.2), value: pullProgress >= 1.0)
            }
        }
        .frame(width: 40, height: 40)
        .opacity(scrollState.isRefreshing ? 1.0 : pullProgress)
        .offset(y: scrollState.safeAreaTop + 20)
        .allowsHitTesting(false)
    }
}

/// Inverted header that slides in when the user scrolls past the info area.
private struct _InvertedHeaderLayer<H: View>: View {
    let scrollState: _ExpandedScrollState
    let headerHeight: CGFloat
    let infoAreaHeight: CGFloat
    let headerView: H

    private var headerCoverProgress: CGFloat {
        let p = (scrollState.scrollOffset - infoAreaHeight) / headerHeight
        return min(max(p, 0), 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            Color(.systemBackground)
                .frame(height: scrollState.safeAreaTop)
                .ignoresSafeArea()

            headerView
                .frame(height: headerHeight)
                .background(Color(.systemBackground))

            Divider().opacity(headerCoverProgress)
        }
        .opacity(headerCoverProgress)
        .allowsHitTesting(headerCoverProgress >= 0.5)
    }
}

// MARK: - Preference Keys

private struct ExpandedScrollOffsetKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#if os(macOS)
private struct _OverlayScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(from: nsView)
        }
    }

    private func configure(from view: NSView) {
        guard let scrollView = view.enclosingScrollView else { return }
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .small
        scrollView.horizontalScroller?.controlSize = .small
        scrollView.verticalScroller?.alphaValue = 0.28
        scrollView.horizontalScroller?.alphaValue = 0.28
        scrollView.drawsBackground = false
    }
}
#endif
