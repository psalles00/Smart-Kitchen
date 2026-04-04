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
    #if os(macOS)
    private let macHeaderTopInset: CGFloat = -14
    private let macHeaderHeight: CGFloat = 34
    private let macBottomInset: CGFloat = 8
    #endif
    private let bottomTabBarContentInset: CGFloat = 84

    // Pull-to-action state
    private let refreshThreshold: CGFloat = 80
    @State private var dragOffset: CGFloat = 0
    @State private var isRefreshing: Bool = false

    private var trailingPanelInset: CGFloat {
        #if os(macOS)
        4
        #else
        leadingPanelInset
        #endif
    }

    #if os(macOS)
    private var macContainerTopGap: CGFloat {
        switch pageTheme {
        case .lists, .recipes, .nutrients:
            18
        case .home:
            0
        }
    }
    #endif

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
                    .frame(height: macHeaderHeight)
                    .padding(.top, macHeaderTopInset)
                    .simultaneousGesture(pullRefreshGesture, including: onRefresh != nil ? .all : .none)

                infoContent()
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 10)

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
                .padding(.top, macContainerTopGap)
                .padding(.horizontal, 16)
                .padding(.bottom, macBottomInset)
            }
        }
        #else
        ZStack(alignment: .top) {
            // FIXED BACKGROUND
            backgroundLayer
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // LAYOUT
            VStack(spacing: 0) {
                // Fixed header (transparent, over shader)
                header(false)
                    .frame(height: headerHeight)
                    .simultaneousGesture(pullRefreshGesture, including: onRefresh != nil ? .all : .none)

                // Shader zone: info + pull handle
                pullableShaderZone

                // Content area (each page manages its own scroll)
                content()
                    .padding(.top, topMargin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: bottomTabBarContentInset)
                    }
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

    // MARK: - Shader Pull Zone

    @ViewBuilder
    private var pullableShaderZone: some View {
        VStack(spacing: 0) {
            infoContent()
                .padding(.horizontal, 20)
                .padding(.top, 4)

            // Pull indicator
            if onRefresh != nil {
                _PullIndicatorView(
                    dragOffset: dragOffset,
                    isRefreshing: isRefreshing,
                    refreshThreshold: refreshThreshold,
                    theme: pageTheme
                )
                .frame(height: max(16, 16 + dragOffset))
            } else {
                Spacer().frame(height: 16)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(pullRefreshGesture, including: onRefresh != nil ? .all : .none)
    }

    private func triggerRefresh() {
        isRefreshing = true
        HapticManager.impact(style: .medium)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dragOffset = 40
        }
        Task {
            await onRefresh?()
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isRefreshing = false
                    dragOffset = 0
                }
            }
        }
    }

    private var pullRefreshGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard onRefresh != nil, !isRefreshing else { return }
                let dy = value.translation.height
                if dy > 0 {
                    withAnimation(.interactiveSpring) {
                        dragOffset = dy
                    }
                }
            }
            .onEnded { _ in
                guard onRefresh != nil, !isRefreshing else { return }
                if dragOffset >= refreshThreshold {
                    triggerRefresh()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = 0
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

// MARK: - Pull Indicator View

/// Pull-to-action indicator shown in the shader area.
private struct _PullIndicatorView: View {
    let dragOffset: CGFloat
    let isRefreshing: Bool
    let refreshThreshold: CGFloat
    let theme: PageTheme

    private var pullProgress: CGFloat {
        guard dragOffset > 0 else { return 0 }
        return min(dragOffset / refreshThreshold, 1.0)
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
                    .scaleEffect(pullProgress >= 1.0 ? 1.3 : 0.6 + pullProgress * 0.4)
                    .animation(.easeInOut(duration: 0.2), value: pullProgress >= 1.0)
            }
        }
        .frame(width: 40, height: 40)
        .opacity(isRefreshing ? 1.0 : pullProgress)
        .allowsHitTesting(false)
    }
}
