import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Expanded Page Layout

/// Layout with a fixed animated background, a floating header, and a
/// content area that manages its own scrolling.
struct ExpandedPageLayout<Header: View, Content: View, InfoContent: View>: View {
    let pageTheme: PageTheme
    let header: (_ isInverted: Bool) -> Header
    let content: () -> Content
    let infoContent: () -> InfoContent
    let startsWithInfoCollapsed: Bool
    var onRefresh: (() async -> Void)? = nil

    private var backgroundManager = BackgroundManager.shared

    private let headerHeight: CGFloat = 60
    private let cornerRadius: CGFloat = 24
    private let topMargin: CGFloat = 10
    private let leadingPanelInset: CGFloat = 8

    // Refresh state
    private let refreshThreshold: CGFloat = 80
    @State private var scrollOffset: CGFloat = 0
    @State private var isRefreshing: Bool = false
    @State private var isRefreshingInternal: Bool = false
    @State private var previousOffset: CGFloat = 0

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
        #if os(macOS)
        ZStack(alignment: .top) {
            backgroundLayer
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                header(false)
                    .frame(height: headerHeight)
                    .padding(.top, 12)

                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(.controlBackgroundColor))

                    VStack(spacing: 0) {
                        Color.clear.frame(height: topMargin)
                        content()
                        Spacer(minLength: 0)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        #else
        ZStack(alignment: .top) {
            // FIXED BACKGROUND
            backgroundLayer
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if onRefresh != nil {
                _PullIndicatorLayer(
                    scrollOffset: scrollOffset,
                    isRefreshing: isRefreshing,
                    refreshThreshold: refreshThreshold,
                    theme: pageTheme
                )
                .padding(.top, 40)
            }

            // LAYOUT
            VStack(spacing: 0) {
                // Fixed header (transparent, over shader)
                header(false)
                    .frame(height: headerHeight)

                infoContent()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                // Content area (each page manages its own scroll)
                content()
                    .coordinateSpace(name: "page_scroll")
                    .onPreferenceChange(PageScrollOffsetKey.self, perform: handleScrollChange)
                    .padding(.top, topMargin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
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
            }
        }
        #endif
    }

    // MARK: - Handlers

    private func handleScrollChange(_ newOffset: CGFloat) {
        let oldOffset = previousOffset
        previousOffset = newOffset

        guard abs(oldOffset - newOffset) > 0.1 else { return }
        scrollOffset = newOffset

        guard let onRefresh, !isRefreshingInternal else { return }
        
        let oldPull = oldOffset
        let newPull = newOffset
        
        // Trigger when pulling down passes threshold and starts springing back
        if oldPull >= refreshThreshold && newPull < oldPull {
            isRefreshingInternal = true
            isRefreshing = true
            HapticManager.impact(style: .medium)
            Task {
                await onRefresh()
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isRefreshingInternal = false
                        isRefreshing = false
                    }
                }
            }
        }
    }

    // MARK: - Background

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

// MARK: - Offset Tracking & Child Views

struct PageScrollOffsetKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PageScrollOffsetReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: PageScrollOffsetKey.self,
                    value: proxy.frame(in: .named("page_scroll")).minY
                )
        }
        .frame(height: 0)
    }
}

/// Pull-to-refresh indicator shown floating over the shader.
private struct _PullIndicatorLayer: View {
    let scrollOffset: CGFloat
    let isRefreshing: Bool
    let refreshThreshold: CGFloat
    let theme: PageTheme

    private var pullProgress: CGFloat {
        guard scrollOffset > 0 else { return 0 }
        return min(scrollOffset / refreshThreshold, 1.0)
    }

    var body: some View {
        VStack {
            if isRefreshing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
            } else {
                Image(systemName: theme == .home ? "sparkles" : "plus.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .scaleEffect(pullProgress >= 1.0 ? 1.1 : 0.9)
                    .animation(.easeInOut(duration: 0.2), value: pullProgress >= 1.0)
            }
        }
        .frame(width: 40, height: 40)
        .opacity(isRefreshing ? 1.0 : pullProgress)
        .allowsHitTesting(false)
    }
}
