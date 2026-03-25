import SwiftUI

// MARK: - Expanded Page Layout

/// Layout where a single ScrollView controls content movement.
/// The animated background stays fixed, and the main content area scrolls over it.
struct ExpandedPageLayout<Header: View, Content: View, InfoContent: View>: View {
    let pageTheme: PageTheme
    let header: (_ isInverted: Bool) -> Header
    let content: () -> Content
    let infoContent: () -> InfoContent
    var onRefresh: (() async -> Void)? = nil

    private var backgroundManager = BackgroundManager.shared

    private let infoAreaHeight: CGFloat = 100
    private let headerHeight: CGFloat = 60
    private let cornerRadius: CGFloat = 24
    private let topMargin: CGFloat = 10

    @State private var scrollOffset: CGFloat = 0

    @State private var isRefreshing: Bool = false
    @State private var pullOffset: CGFloat = 0
    private let refreshThreshold: CGFloat = 80

    init(
        pageTheme: PageTheme,
        @ViewBuilder header: @escaping (_ isInverted: Bool) -> Header,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder infoContent: @escaping () -> InfoContent,
        onRefresh: (() async -> Void)? = nil
    ) {
        self.pageTheme = pageTheme
        self.header = header
        self.content = content
        self.infoContent = infoContent
        self.onRefresh = onRefresh
    }

    private var totalRevealHeight: CGFloat {
        headerHeight + infoAreaHeight
    }

    private var headerCoverProgress: CGFloat {
        let progress = (scrollOffset - infoAreaHeight) / headerHeight
        return min(max(progress, 0), 1)
    }

    private var pullProgress: CGFloat {
        guard pullOffset > 0 else { return 0 }
        return min(pullOffset / refreshThreshold, 1.0)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // 1. FIXED BACKGROUND LAYER
                VStack(spacing: 0) {
                    backgroundLayer
                        .frame(height: geometry.size.height * 0.75)
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)

                // 2. SCROLL LAYER
                ScrollView {
                    VStack(spacing: 0) {
                        // Pull-to-refresh trigger zone
                        GeometryReader { pullGeo in
                            let pullOffset = pullGeo.frame(in: .global).minY - geometry.safeAreaInsets.top
                            Color.clear
                                .preference(key: ExpandedPullToRefreshKey.self, value: pullOffset)
                        }
                        .frame(height: 0)

                        // Transparent spacer that pushes content down
                        Color.clear
                            .frame(height: totalRevealHeight)
                            .overlay(alignment: .top) {
                                GeometryReader { geo in
                                    let minY = geo.frame(in: .named("expanded_scroll")).minY

                                    VStack(spacing: 0) {
                                        header(false)
                                            .frame(height: headerHeight)
                                            .opacity(1 - headerCoverProgress)

                                        infoArea
                                            .frame(height: infoAreaHeight)
                                            .opacity(max(0.0, 1.0 - (scrollOffset / (infoAreaHeight * 0.5))))
                                    }
                                    .offset(y: -minY)
                                }
                            }

                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: topMargin + (headerCoverProgress * headerHeight))

                            content()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height - headerHeight)
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
                .scrollIndicators(.hidden)
                .coordinateSpace(name: "expanded_scroll")
                .onPreferenceChange(ExpandedScrollOffsetKey.self) { value in
                    scrollOffset = value
                }
                .onPreferenceChange(ExpandedPullToRefreshKey.self) { value in
                    let previousPull = pullOffset
                    pullOffset = max(0, value)

                    if let _ = onRefresh, !isRefreshing {
                        if previousPull >= refreshThreshold && value < previousPull {
                            triggerRefresh()
                        }
                    }
                }

                // Refresh indicator overlay
                if pullProgress > 0 || isRefreshing {
                    VStack {
                        if isRefreshing {
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
                    .opacity(isRefreshing ? 1.0 : pullProgress)
                    .offset(y: geometry.safeAreaInsets.top + 20)
                }

                // 3. INVERTED HEADER (appears when scrolling past)
                if headerCoverProgress > 0 {
                    VStack(spacing: 0) {
                        Color(.systemBackground)
                            .frame(height: geometry.safeAreaInsets.top)
                            .ignoresSafeArea()

                        header(true)
                            .frame(height: headerHeight)
                            .background(Color(.systemBackground))

                        Divider().opacity(headerCoverProgress)
                    }
                    .opacity(headerCoverProgress)
                    .zIndex(10)
                }
            }
        }
    }

    // MARK: - Refresh Logic

    private func triggerRefresh() {
        guard let onRefresh = onRefresh, !isRefreshing else { return }

        isRefreshing = true
        HapticManager.impact(style: .medium)

        Task {
            await onRefresh()
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    isRefreshing = false
                }
            }
        }
    }

    // MARK: - Subviews

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
            TexturedGradientView(preset: .ocean, progress: 1.0)
        case .recipes:
            TexturedGradientView(preset: .sunset, progress: 1.0)
        case .nutrients:
            MeshGradientShaderView(progress: 1.0)
        }
    }

    private var infoArea: some View {
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
}

// MARK: - Preference Keys

private struct ExpandedScrollOffsetKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ExpandedPullToRefreshKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
