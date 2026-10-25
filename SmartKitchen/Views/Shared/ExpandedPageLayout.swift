import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension View {
    /// Ask the system to release the vertical status region, without ignoring
    /// camera, keyboard or navigation safe areas. Other platforms keep their chrome.
    @ViewBuilder
    func savoriaSystemChrome() -> some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            modifier(SavoriaVerticalSystemChrome())
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if os(iOS)
@available(iOS 27.1, *)
private struct SavoriaVerticalSystemChrome: ViewModifier {
    @State private var prefersVerticalBar = false

    func body(content: Content) -> some View {
        content
            .environment(\.savoriaVerticalChrome, prefersVerticalBar)
            .statusBarHidden(prefersVerticalBar)
            // The app's paired pages and assistant field use a horizontal flow.
            // Keep the native tabs horizontal instead of reserving a side rail.
            .toolbarVerticalBehavior(.disabled)
            .background {
                SavoriaPreferredBarEdgeReader { prefersVerticalBar = $0 }
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

/// Read the system's preferred edge, which remains available when the app opts
/// out of vertical toolbars. Reading the current SwiftUI bar edge after opting
/// out would report nil and make the status preference alternate on rotation.
@available(iOS 27.1, *)
private struct SavoriaPreferredBarEdgeReader: UIViewRepresentable {
    let onChange: (Bool) -> Void

    func makeUIView(context: Context) -> EdgeView { EdgeView() }
    func updateUIView(_ view: EdgeView, context: Context) {
        view.onChange = onChange
        view.reportPreferredEdge()
    }

    final class EdgeView: UIView {
        var onChange: ((Bool) -> Void)?
        private var lastValue: Bool?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) {
                (view: EdgeView, _: UITraitCollection) in view.reportPreferredEdge()
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reportPreferredEdge()
        }
        func reportPreferredEdge() {
            guard let window else { return }
            // The hosting view can override its traits when opting out. The
            // containing window retains the system's preferred placement.
            let value = window.traitCollection.verticalBarEdge != .unspecified
            guard value != lastValue else { return }
            lastValue = value
            Task { @MainActor [weak self] in self?.onChange?(value) }
        }
    }
}
#endif

/// Only the chrome row enters the camera band. Its controls avoid the actual
/// native occlusion; the remainder of the page keeps the full available width.
private struct SavoriaVerticalChromeKey: EnvironmentKey { static let defaultValue = false }
private struct SavoriaTopOcclusionExtentKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    var savoriaTopOcclusionExtent: CGFloat {
        get { self[SavoriaTopOcclusionExtentKey.self] }
        set { self[SavoriaTopOcclusionExtentKey.self] = newValue }
    }
    var savoriaVerticalChrome: Bool {
        get { self[SavoriaVerticalChromeKey.self] }
        set { self[SavoriaVerticalChromeKey.self] = newValue }
    }
}
struct SavoriaCameraBandContent: ViewModifier {
    var enabled = true
    @Environment(\.savoriaVerticalChrome) private var verticalChrome
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.savoriaTopOcclusionExtent, topOcclusion(geometry))
        }
        .ignoresSafeArea(.container, edges: enabled && verticalChrome ? .top : [])
    }
    private func topOcclusion(_ geometry: GeometryProxy) -> CGFloat {
        #if os(iOS)
        if #available(iOS 27.1, *), enabled && verticalChrome {
            let bounds = CGRect(origin: .zero, size: geometry.size)
            return geometry.reservedRegions(kind: .occlusion)
                .filter { $0.frame.intersects(bounds) && $0.frame.maxY <= bounds.midY }
                .map { $0.frame.maxY }.max() ?? 0
        }
        #endif
        return 0
    }
}
struct SavoriaCameraHeader<Content: View>: View {
    let height: CGFloat
    @ViewBuilder var content: () -> Content
    @Environment(\.savoriaTopOcclusionExtent) private var cameraBottom
    var body: some View {
        GeometryReader { geometry in
            let clearance = cameraClearance(geometry)
            content()
                .padding(.leading, clearance.leading)
                .padding(.trailing, clearance.trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: max(height, cameraBottom > 0 ? cameraBottom + 8 : height))
    }
    private func cameraClearance(_ geometry: GeometryProxy) -> EdgeInsets {
        var insets = EdgeInsets()
        #if os(iOS)
        if #available(iOS 27.1, *) {
            for region in geometry.reservedRegions(kind: .occlusion) {
                let rect = region.frame
                guard rect.intersects(CGRect(origin: .zero, size: geometry.size)) else { continue }
                if rect.midX > geometry.size.width / 2 {
                    insets.trailing = max(insets.trailing, geometry.size.width - rect.minX + 8)
                } else { insets.leading = max(insets.leading, rect.maxX + 8) }
            }
        }
        #endif
        return insets
    }
}

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

struct ContentPanelWavyBorderKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: Color?

    static func reduce(value: inout Color?, nextValue: () -> Color?) {
        value = nextValue() ?? value
    }
}

enum ExpandedPageHeaderMetrics {
    static let iosTitleHeight: CGFloat = 60
    static let iosInfoTopPadding: CGFloat = 4
    static let iosInfoBottomGap: CGFloat = 16
    static let iosEmptyInfoHeight: CGFloat = 0
    static let iosCompactInfoHeight: CGFloat = 44
    static let iosHomeInfoHeight: CGFloat = 44

    static func iosHeaderDetailHeight(infoHeight: CGFloat) -> CGFloat {
        iosInfoTopPadding + infoHeight + iosInfoBottomGap
    }

    static func iosTotalHeight(infoHeight: CGFloat) -> CGFloat {
        iosTitleHeight + iosHeaderDetailHeight(infoHeight: infoHeight)
    }
}

// MARK: - Expanded Page Layout

/// Layout with a fixed page background, a floating header, and a
/// content area that manages its own scrolling.
struct ExpandedPageLayout<Header: View, Content: View, InfoContent: View>: View {
    let pageTheme: PageTheme
    let header: (_ isInverted: Bool) -> Header
    let content: () -> Content
    let infoContent: () -> InfoContent
    let startsWithInfoCollapsed: Bool
    let backgroundOverride: AnyView?
    let companionTitle: String
    let companionSubtitle: String
    let companion: (() -> AnyView)?
    let companionPage: (() -> AnyView)?
    let primaryFraction: CGFloat
    let arrangesCompanion: Bool
    @Environment(\.savoriaWorkspacePane) private var isWorkspacePane
    @Environment(\.savoriaWorkspaceExpanded) private var workspaceExpanded
    @Environment(\.savoriaWorkspacePageActive) private var workspacePageActive
    @State private var detailZoneHeight: CGFloat = 0

    private var usesWorkspace: Bool {
        #if os(iOS)
        workspaceExpanded && pageTheme != .settings && arrangesCompanion
        #else
        false
        #endif
    }

    private var isWorkspacePanel: Bool { workspaceExpanded || isWorkspacePane }

    #if !os(iOS)
    @Environment(\.backgroundTheme) private var backgroundTheme
    #endif
    @Environment(\.searchOverlay) private var searchOverlay
    @EnvironmentObject private var searchBarState: SearchBarState

    #if !os(iOS)
    private var effectiveBgTheme: PageTheme { backgroundTheme ?? pageTheme }
    #endif

    private var usesDescriptionHeader: Bool { pageTheme == .home || pageTheme == .nutrients }
    private var infoTopPadding: CGFloat { usesDescriptionHeader ? 0 : ExpandedPageHeaderMetrics.iosInfoTopPadding }
    private var infoBottomGap: CGFloat { usesDescriptionHeader ? 8 : ExpandedPageHeaderMetrics.iosInfoBottomGap }

    private let headerHeight: CGFloat = ExpandedPageHeaderMetrics.iosTitleHeight
    private let cornerRadius: CGFloat = 24
    private let topMargin: CGFloat = 10
    private let leadingPanelInset: CGFloat = 0
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

    private var trailingPanelInset: CGFloat {
        #if os(macOS)
        4
        #else
        leadingPanelInset
        #endif
    }

    #if os(macOS)
    private var macContainerTopGap: CGFloat {
        usesDescriptionHeader ? 8 : 18
    }
    #endif

    init(
        pageTheme: PageTheme,
        startsWithInfoCollapsed: Bool = false,
        backgroundOverride: AnyView? = nil,
        companionTitle: String = String(localized: "Despensa"),
        companionSubtitle: String = String(localized: "Seu estoque, ao lado"),
        companion: (() -> AnyView)? = nil,
        companionPage: (() -> AnyView)? = nil,
        primaryFraction: CGFloat = 0.5,
        arrangesCompanion: Bool = true,
        @ViewBuilder header: @escaping (_ isInverted: Bool) -> Header,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder infoContent: @escaping () -> InfoContent
    ) {
        self.pageTheme = pageTheme
        self.startsWithInfoCollapsed = startsWithInfoCollapsed
        self.backgroundOverride = backgroundOverride
        self.companionTitle = companionTitle
        self.companionSubtitle = companionSubtitle
        self.companion = companion
        self.companionPage = companionPage
        self.primaryFraction = primaryFraction
        self.arrangesCompanion = arrangesCompanion
        self.header = header
        self.content = content
        self.infoContent = infoContent
    }



    var body: some View {
        #if os(macOS)
        primaryBody
        #else
        if isWorkspacePane {
            // Reuse the feature's original controls/content in the shared page.
            // It owns no second page title, description or rounded outer surface.
            VStack(spacing: 0) {
                infoContent()
                content()
            }
        } else {
            primaryBody
                .modifier(SavoriaCameraBandContent())
        }
        #endif
    }

    @ViewBuilder
    private var workspaceContent: some View {
        #if os(iOS)
        if usesWorkspace {
            if #available(iOS 27.1, *) {
                ArrangementView {
                    content()
                        .splitArrangementLayoutRatio(primaryFraction)
                        .overlay(alignment: .trailing) { Color.primary.opacity(0.08).frame(width: 1).allowsHitTesting(false) }
                        .accessibilityIdentifier("savoria.workspace.primary")
                } secondary: {
                    secondaryPane.splitArrangementLayoutRatio(1 - primaryFraction)
                        .accessibilityIdentifier("savoria.workspace.secondary")
                }
                .arrangementViewStyle(SavoriaWorkspaceArrangement(expanded: true))
            } else {
                HStack(spacing: 0) {
                    content().frame(maxWidth: .infinity)
                    Divider()
                    secondaryPane.frame(maxWidth: .infinity)
                }
            }
        } else { content() }
        #else
        content()
        #endif
    }

    @ViewBuilder
    private var secondaryPane: some View {
        if usesWorkspace && workspacePageActive {
            Group {
                if let companionPage { companionPage() }
                else if let companion { companion() }
                else { AnyView(EmptyView()) }
            }
            .environment(\.savoriaWorkspaceExpanded, false)
            .environment(\.savoriaWorkspacePane, true)
            .environment(\.searchOverlay, nil)
        } else { Color.clear }
    }

    private var primaryBody: some View {
        #if os(macOS)
        ZStack(alignment: .top) {
            if !isWorkspacePane { backgroundLayer.ignoresSafeArea().allowsHitTesting(false) }

            VStack(spacing: 0) {
                header(false)
                    .frame(height: macHeaderHeight)
                    .padding(.top, macHeaderTopInset)

                infoContent()
                    .padding(.horizontal, 20)
                    .padding(.top, usesDescriptionHeader ? 0 : 4)
                    .padding(.bottom, usesDescriptionHeader ? 0 : 10)

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
                // Standalone pages keep a local backdrop. Tabs share the app field.
                if !isWorkspacePane { backgroundLayer.ignoresSafeArea().allowsHitTesting(false) }

                // LAYOUT
                VStack(spacing: 0) {
                    // Fixed header (transparent, over background)
                    SavoriaCameraHeader(height: headerHeight) { header(false) }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("savoria.page.header")

                    // Header zone: info content + search bar slot
                    headerDetailZone
                        .frame(minHeight: 0, alignment: .top)
                        .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { detailZoneHeight = $0 }

                    // Content area
                    contentArea
                }
            }
        .onAppear {
            if !isWorkspacePane { searchBarState.pageContext = pageTheme.searchContext }
    }
        .modifier(SavoriaPageContainerBackground())
    #endif
}

    // MARK: - Header Detail Zone (iOS)

    #if !os(macOS)
    @ViewBuilder
    private var headerDetailZone: some View {
        VStack(spacing: 0) {
            infoContent()
                .padding(.horizontal, 20)
                .padding(.top, infoTopPadding)

            Spacer().frame(height: infoBottomGap)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
    #endif

    // MARK: - Content Area (iOS)

    #if !os(macOS)
    private var contentArea: some View {
        ZStack(alignment: .top) {
            workspaceContent
                .padding(.top, topMargin)

            // Search results rendered inside the content panel
            if searchBarState.isVisible, let searchOverlay {
                searchOverlay
                    .padding(.top, topMargin)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: isWorkspacePanel ? 16 : bottomTabBarContentInset)
        }
        .background {
            SavoriaColumnSurface(theme: pageTheme, cornerRadius: cornerRadius)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: isWorkspacePanel ? cornerRadius : 0,
                bottomTrailingRadius: isWorkspacePanel ? cornerRadius : 0,
                topTrailingRadius: cornerRadius
            )
        )
        .overlay {
            SavoriaColumnBorder(theme: pageTheme, cornerRadius: cornerRadius)
        }
        .overlayPreferenceValue(ContentPanelWavyBorderKey.self) { borderColor in
            if let borderColor {
                WavyPanelBorder(inset: -2)
                    .stroke(borderColor, lineWidth: 1.4)
                    .allowsHitTesting(false)
            }
        }

        .padding(.bottom, isWorkspacePanel ? 8 : 0)
        .padding(.leading, leadingPanelInset)
        .padding(.trailing, trailingPanelInset)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: searchBarState.isVisible)
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
            #if os(iOS)
            // Draw inside the native page host: making navigation clear
            // alone does not make the enclosing TabView host transparent.
            ActivePageBackground(pageTheme: pageTheme)
            #else
            ZStack {
                themedBackground(for: backgroundFromTheme)

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
            #endif
        }
    }

    @ViewBuilder
    private func themedBackground(for theme: PageTheme) -> some View {
        ThemedBackgroundView(
            theme: theme,
            progress: 1.0
        )
    }
}

// MARK: - Deferred Tab Loading

#if os(iOS)
/// Let SwiftUI manage navigation hosting and its interaction regions.
private struct SavoriaPageContainerBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.containerBackground(.clear, for: .navigation)
        } else {
            content
        }
    }
}

/// Theme/visibility changes belong to the background leaf, not to page content
/// builders that group lists or walk the nutrition history.
private struct ActivePageBackground: View {
    let pageTheme: PageTheme
    @Environment(\.backgroundTheme) private var backgroundTheme
    @Environment(\.visiblePageTheme) private var visiblePageTheme

    var body: some View {
        let theme = backgroundTheme ?? pageTheme
        ThemedBackgroundView(theme: theme,
                             animates: visiblePageTheme == nil || visiblePageTheme == pageTheme)
            .animation(.easeInOut(duration: 0.55), value: theme)
    }
}
#endif

struct DeferredTabPage<Loaded: View, Placeholder: View>: View {
    let tab: AppTab
    @ViewBuilder var loaded: () -> Loaded
    @ViewBuilder var placeholder: () -> Placeholder

    @Environment(\.activeAppTab) private var activeAppTab
    @State private var isReady = false

    init(
        tab: AppTab,
        initiallyReady: Bool = false,
        @ViewBuilder loaded: @escaping () -> Loaded,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.tab = tab
        self.loaded = loaded
        self.placeholder = placeholder
        _isReady = State(initialValue: initiallyReady)
    }

    var body: some View {
        #if os(iOS)
        Group {
            if isReady {
                loaded()
                    .onAppear {
                        ActionTrace.shared.mark(page: tab.rawValue, phase: "loaded")
                    }
            } else {
                placeholder()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            updateReadiness(for: activeAppTab)
        }
        .onChange(of: activeAppTab) { _, newValue in
            updateReadiness(for: newValue)
        }
        #else
        loaded()
        #endif
    }

    #if os(iOS)
    private func updateReadiness(for activeTab: AppTab?) {
        guard activeTab == tab else {
            return
        }
        // Prepare content as soon as selected; retain it across tab/scene changes.
        // A fixed sleep made even an otherwise fast first visit feel unresponsive.
        guard !isReady else { return }
        isReady = true
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
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(skeletonStrokeColor, lineWidth: 0.6)
                        }
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
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(skeletonStrokeColor, lineWidth: 0.6)
                }
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
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(skeletonStrokeColor, lineWidth: 0.6)
        }
    }
}

struct NutritionPageSkeleton: View {
    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width - 32)

            ScrollView(.vertical) {
                VStack(spacing: 14) {
                    NutritionDateStripeSkeleton()
                        .frame(width: contentWidth)
                        .padding(.bottom, -2)

                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(skeletonBaseColor)
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(skeletonStrokeColor, lineWidth: 0.6)
                        }
                        .frame(width: contentWidth, height: 176)

                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(skeletonBaseColor)
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(skeletonStrokeColor, lineWidth: 0.6)
                            }
                            .frame(height: 108)
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(skeletonBaseColor)
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(skeletonStrokeColor, lineWidth: 0.6)
                            }
                            .frame(height: 108)
                    }
                    .frame(width: contentWidth)

                    ForEach(0..<5, id: \.self) { index in
                        SkeletonListRow(index: index)
                            .frame(width: contentWidth)
                            .background(skeletonBaseColor.opacity(0.55), in: .rect(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(skeletonStrokeColor, lineWidth: 0.6)
                            }
                    }
                }
                .frame(width: geometry.size.width, alignment: .top)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .skeletonShimmer()
        .clipped()
        .allowsHitTesting(false)
    }
}

private struct NutritionDateStripeSkeleton: View {
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(skeletonStrokeColor, lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(skeletonBaseColor.opacity(0.36))
                )
                .frame(width: 38, height: 42)
                .frame(width: 44)

            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(skeletonBaseColor.opacity(index == 5 ? 0.78 : 0.55))
                            .frame(width: 12, height: 8)

                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(index == 5 ? skeletonHighlightColor : skeletonBaseColor.opacity(0.72))
                            .frame(width: 38, height: 28)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 74)
    }
}

struct NutritionInfoSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 6).fill(skeletonHeaderBaseColor).frame(height: 13)
            RoundedRectangle(cornerRadius: 6).fill(skeletonHeaderBaseColor).frame(height: 13)
                .padding(.trailing, 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: ExpandedPageHeaderMetrics.iosHomeInfoHeight, alignment: .topLeading)
        .skeletonShimmer()
        .allowsHitTesting(false)
    }
}

struct AssistantInfoSkeleton: View {
    var body: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 6).fill(skeletonHeaderBaseColor).frame(height: 13)
            RoundedRectangle(cornerRadius: 6).fill(skeletonHeaderBaseColor).frame(height: 13)
                .padding(.trailing, 50)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: ExpandedPageHeaderMetrics.iosHomeInfoHeight)
        .skeletonShimmer()
        .allowsHitTesting(false)
        #else
        HStack(alignment: .center, spacing: 12) {
            GeometryReader { proxy in
                let primaryWidth = max(min(proxy.size.width * 0.7, 240), 170)
                let secondaryWidth = primaryWidth * 0.78

                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(skeletonHeaderBaseColor.opacity(0.86))
                        .frame(width: primaryWidth, height: 14)

                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(skeletonHeaderBaseColor.opacity(0.86))
                            .frame(width: 72, height: 12)

                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(skeletonHeaderBaseColor.opacity(0.86))
                            .frame(width: 70, height: 12)

                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(skeletonHeaderBaseColor.opacity(0.86))
                            .frame(width: secondaryWidth * 0.32, height: 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, -8)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .stroke(skeletonHeaderBaseColor.opacity(0.62), lineWidth: 5)

                Circle()
                    .trim(from: 0, to: 0.68)
                    .stroke(skeletonHeaderHighlightColor.opacity(0.72), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(skeletonHeaderBaseColor)
                        .frame(width: 24, height: 10)

                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(skeletonHeaderBaseColor.opacity(0.82))
                        .frame(width: 20, height: 7)
                }
            }
            .frame(width: 46, height: 46)
            .padding(.top, -6)
            .padding(.bottom, 6)
        }
        .padding(.bottom, -3)
        .frame(height: 47)
        .skeletonShimmer()
        .allowsHitTesting(false)
        #endif
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
                .stroke(skeletonStrokeColor, lineWidth: 4)
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

private extension View {
    func skeletonShimmer() -> some View {
        appSkeletonShimmer()
    }
}

private var skeletonBaseColor: Color {
    appSkeletonSurfaceBaseColor
}

private var skeletonHighlightColor: Color {
    appSkeletonSurfaceHighlightColor
}

private var skeletonStrokeColor: Color {
    appSkeletonSurfaceStrokeColor
}

private var skeletonHeaderBaseColor: Color {
    appSkeletonHeaderBaseColor
}

private var skeletonHeaderHighlightColor: Color {
    appSkeletonHeaderHighlightColor
}

// MARK: - Adaptive kitchen workspace

private struct SavoriaWorkspaceExpandedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SavoriaWorkspacePageActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var savoriaWorkspacePageActive: Bool {
        get { self[SavoriaWorkspacePageActiveKey.self] }
        set { self[SavoriaWorkspacePageActiveKey.self] = newValue }
    }
    var savoriaWorkspaceExpanded: Bool {
        get { self[SavoriaWorkspaceExpandedKey.self] }
        set { self[SavoriaWorkspaceExpandedKey.self] = newValue }
    }
}

enum SavoriaWorkspaceMetrics {
    static func supportsCompanion(geometry: GeometryProxy, accessibilitySize: Bool = false) -> Bool {
        var horizontalDivision = false
        #if os(iOS)
        if #available(iOS 27.1, *) {
            horizontalDivision = geometry.reservedRegions(kind: .division, options: .includeInactive)
                .contains { $0.frame.width > $0.frame.height }
        }
        #endif
        return supportsCompanion(size: CGSize(width: geometry.size.width,
                                              height: geometry.size.height + geometry.safeAreaInsets.bottom),
                                 accessibilitySize: accessibilitySize, horizontalDivision: horizontalDivision)
    }

    /// Window geometry, never device models or screen bounds. Narrow windows
    /// retain every operation in the primary page. No forced size classes.
    static func supportsCompanion(size: CGSize, accessibilitySize: Bool = false,
                                  horizontalDivision: Bool = false) -> Bool {
        !accessibilitySize && ((size.width >= 740 && size.height >= 600) ||
                              (horizontalDivision && size.width >= 540 && size.height >= 740))
    }
}

#if os(iOS)
@available(iOS 27.1, *)
private struct SavoriaWorkspaceArrangement: ArrangementViewStyle {
    let expanded: Bool
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if expanded {
            // The system handles horizontal/vertical folds and reserved regions.
            SplitArrangementViewStyle().makeBody(configuration: configuration)
        } else {
            configuration.primary
        }
    }
}
#endif

/// One recipe selection projected into compact navigation when required.
struct SavoriaRecipeWorkspaceNavigation {
    var selection: UUID?
    var path: [UUID] = []
    mutating func open(_ id: UUID, expanded: Bool) {
        selection = id
        path = expanded ? [] : [id]
    }
    mutating func resize(expanded: Bool) {
        if expanded { selection = path.last ?? selection; path = [] }
        else { path = selection.map { [$0] } ?? [] }
    }
    mutating func stackChanged(expanded: Bool) {
        if let id = path.last { selection = id }
        else if !expanded { selection = nil }
    }
}

private struct SavoriaWorkspaceRecipeSelectionKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: Binding<UUID?>? = nil
}

extension EnvironmentValues {
    var savoriaWorkspaceRecipeSelection: Binding<UUID?>? {
        get { self[SavoriaWorkspaceRecipeSelectionKey.self] }
        set { self[SavoriaWorkspaceRecipeSelectionKey.self] = newValue }
    }
}

/// Reuse the original feature page, including its header, tabs, search, filters,
/// selection, sheets, rows and actions. Only its placement/chrome is adapted.
struct SavoriaOriginalListPane: View {
    let initialSubtab: ListSubtab
    var selection: Binding<ListSubtab>? = nil
    var body: some View {
        ListsTabView(initialSubtab: initialSubtab, selection: selection)
            .environment(\.activeAppTab, .lists)
            .environment(\.savoriaWorkspaceExpanded, false)
            .environment(\.savoriaWorkspacePane, true)
            .environment(\.searchOverlay, nil)
            .environment(\.scrollToItem, nil)
    }
}

private struct SavoriaWorkspacePaneKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var savoriaWorkspacePane: Bool {
        get { self[SavoriaWorkspacePaneKey.self] }
        set { self[SavoriaWorkspacePaneKey.self] = newValue }
    }
}

/// Keep one search field inside the primary display region. Measure the local
/// container, including native division geometry, without taking vertical space.
struct SavoriaWorkspaceAccessory<Content: View>: View {
    let expanded: Bool
    @ViewBuilder let content: () -> Content
    @State private var primaryWidth: CGFloat? = nil
    var body: some View {
        content()
            .frame(maxWidth: expanded ? primaryWidth : .infinity)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                #if os(iOS)
                if #available(iOS 27.1, *),
                   let division = proxy.reservedRegions(kind: .division, options: .includeInactive).first {
                    if division.frame.height > division.frame.width {
                        return max(division.frame.minX, 0)
                    }
                    return proxy.size.width
                }
                #endif
                return max((proxy.size.width - 16) / 2, 0)
            } action: { primaryWidth = $0 }
    }
}
