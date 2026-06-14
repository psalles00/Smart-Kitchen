import SwiftUI

/// Initial splash screen displayed while the app warms up its data layer
/// (SwiftData/CloudKit container, seeders, migrations, backup recovery).
///
/// The splash blocks navigation so the user never lands on a half-loaded
/// dashboard while bootstrap work runs in the background.
struct SplashView: View {
    var body: some View {
        let _ = PerformanceLogger.event(.launch, "SplashView body evaluated")
        return ZStack {
            ThemedBackgroundView(
                theme: .home,
                progress: 1.0
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            #if os(iOS)
            AppLaunchSkeletonPage(kind: .assistant)
                .launchSkeletonStatusBar()
            #else
            AppLaunchSkeletonPage(kind: .assistant)
            #endif
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Savoria")
    }
}

enum AppSkeletonKind {
    case assistant
    case lists
    case recipes
    case nutrition

    var title: String {
        switch self {
        case .assistant:
            return "Savoria"
        case .lists:
            return String(localized: "Listas")
        case .recipes:
            return String(localized: "Receitas")
        case .nutrition:
            return String(localized: "Nutrição")
        }
    }

    var showsHeaderDetail: Bool {
        switch self {
        case .assistant, .nutrition:
            return true
        case .lists, .recipes:
            return false
        }
    }

    var pageTheme: PageTheme {
        switch self {
        case .assistant:
            return .home
        case .lists:
            return .lists
        case .recipes:
            return .recipes
        case .nutrition:
            return .nutrients
        }
    }
}

enum AppSkeletonPresentation {
    case fullPage
    case contentOnly
}

struct AppLaunchSkeletonPage: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var shimmerPhase: CGFloat = 0
    @State private var shortcutDeckWidth: CGFloat = 0

    let kind: AppSkeletonKind
    let title: String
    let presentation: AppSkeletonPresentation

    private let cornerRadius: CGFloat = 24

    init(kind: AppSkeletonKind = .assistant, title: String? = nil, presentation: AppSkeletonPresentation = .fullPage) {
        self.kind = kind
        self.title = title ?? kind.title
        self.presentation = presentation
    }

    var body: some View {
        let _ = PerformanceLogger.event(.launch, "AppLaunchSkeletonPage body evaluated")
        return skeletonBody
        .allowsHitTesting(false)
        .onAppear(perform: startShimmer)
    }

    @ViewBuilder
    private var skeletonBody: some View {
        switch presentation {
        case .fullPage:
            #if os(macOS)
            macLayout
            #else
            iosLayout
            #endif
        case .contentOnly:
            contentOnlyLayout
        }
    }

    private var contentOnlyLayout: some View {
        ScrollView {
            contentStack
                .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
    }

    #if os(macOS)
    private let macHeaderTopInset: CGFloat = -14
    private let macHeaderHeight: CGFloat = 34
    private let macBottomInset: CGFloat = 8
    private let macContainerTopGap: CGFloat = 18

    private var macLayout: some View {
        VStack(spacing: 0) {
            PageHeader(title: title, isInverted: false) {
                SkeletonBlock(width: 34, height: 34, cornerRadius: 17, palette: .header, phase: shimmerPhase)
            }
            .frame(height: macHeaderHeight)
            .padding(.top, macHeaderTopInset)

            headerDetailContent
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 10)

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(skeletonContentBackground)

                VStack(spacing: 0) {
                    Color.clear.frame(height: 10)
                    ScrollView {
                        contentStack
                            .padding(.top, 12)
                    }
                    .scrollIndicators(.hidden)
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
    private let headerHeight: CGFloat = 60
    private let topMargin: CGFloat = 10
    private let leadingPanelInset: CGFloat = 8
    private let bottomTabBarContentInset: CGFloat = 130

    private var iosLayout: some View {
        VStack(spacing: 0) {
            PageHeader(title: title, isInverted: false) {
                SkeletonBlock(width: 34, height: 36, cornerRadius: 18, palette: .header, phase: shimmerPhase)
            }
            .frame(height: headerHeight)

            VStack(spacing: 0) {
                headerDetailContent
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                Spacer().frame(height: 16)
            }
            .frame(maxWidth: .infinity)

            ZStack(alignment: .top) {
                ScrollView {
                    contentStack
                        .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
                .padding(.top, topMargin)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: bottomTabBarContentInset)
            }
            .background(skeletonContentBackground)
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
            .padding(.trailing, leadingPanelInset)
        }
    }
    #endif

    @ViewBuilder
    private var headerDetailContent: some View {
        switch kind {
        case .assistant:
            assistantInfoContent
        case .nutrition:
            nutritionInfoContent
        case .lists, .recipes:
            Color.clear.frame(height: ExpandedPageHeaderMetrics.iosEmptyInfoHeight)
        }
    }

    private var assistantInfoContent: some View {
        GeometryReader { proxy in
            let primaryWidth = max(min(proxy.size.width * 0.7, 240), 170)
            let secondaryWidth = primaryWidth * 0.78

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBlock(width: primaryWidth, height: 18, cornerRadius: 9, palette: .header, phase: shimmerPhase)

                    HStack(spacing: 10) {
                        SkeletonBlock(width: 72, height: 12, cornerRadius: 6, palette: .header, phase: shimmerPhase)
                        SkeletonBlock(width: 70, height: 12, cornerRadius: 6, palette: .header, phase: shimmerPhase)
                        SkeletonBlock(width: secondaryWidth * 0.32, height: 12, cornerRadius: 6, palette: .header, phase: shimmerPhase)
                    }
                }

                Spacer(minLength: 0)

                calorieRingPlaceholder
            }
        }
        .frame(height: 60)
    }

    private var nutritionInfoContent: some View {
        HStack(spacing: 12) {
            SkeletonBlock(width: nil, height: 28, cornerRadius: 14, palette: .header, phase: shimmerPhase)
                .frame(maxWidth: .infinity)
            SkeletonBlock(width: 92, height: 32, cornerRadius: 16, palette: .header, phase: shimmerPhase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: ExpandedPageHeaderMetrics.iosCompactInfoHeight)
    }

    private var calorieRingPlaceholder: some View {
        ZStack {
            Circle()
                .stroke(headerRingTrackColor, lineWidth: 4)

            Circle()
                .trim(from: 0, to: 0.68)
                .stroke(headerRingProgressColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                SkeletonBlock(width: 26, height: 12, cornerRadius: 6, palette: .header, phase: shimmerPhase)
                SkeletonBlock(width: 18, height: 7, cornerRadius: 3.5, palette: .header, phase: shimmerPhase)
            }
        }
        .frame(width: 54, height: 54)
    }

    private var contentStack: some View {
        Group {
            switch kind {
            case .assistant:
                assistantContentStack
            case .lists:
                listsContentStack
            case .recipes:
                recipesContentStack
            case .nutrition:
                nutritionContentStack
            }
        }
    }

    private var assistantContentStack: some View {
        VStack(alignment: .leading, spacing: 32) {
            actionDeck
            pendingNutritionSection
            expiringSection
            suggestedRecipesSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }

    private var listsContentStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            segmentedControlSkeleton(widths: [86, 92, 78])
                .padding(.bottom, 4)

            SkeletonPanel(cornerRadius: 18) {
                VStack(spacing: 0) {
                    ForEach(0..<9, id: \.self) { index in
                        listRowSkeleton(index: index, showsIcon: true, showsTrailingCircle: index < 6)

                        if index < 8 {
                            ItemListDivider()
                                .padding(.leading, 70)
                                .padding(.trailing, 14)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }

    private var recipesContentStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chipSkeleton(width: 74, palette: .accent)
                    chipSkeleton(width: 86)
                    chipSkeleton(width: 68)
                    chipSkeleton(width: 92)
                    chipSkeleton(width: 76)
                }
                .padding(.vertical, 1)
            }

            GeometryReader { proxy in
                let spacing: CGFloat = 1
                let cardWidth = max((proxy.size.width - spacing * 2) / 3, 0)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3),
                    spacing: spacing
                ) {
                    ForEach(0..<12, id: \.self) { index in
                        recipeGridCard(index: index, width: cardWidth)
                    }
                }
            }
            .frame(height: 620)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }

    private var nutritionContentStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            nutritionDateStripe

            SkeletonPanel(cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            SkeletonBlock(width: 112, height: 16, cornerRadius: 8, palette: .surface, phase: shimmerPhase)
                            SkeletonBlock(width: 178, height: 12, cornerRadius: 6, palette: .surface, phase: shimmerPhase)
                        }

                        Spacer(minLength: 0)

                        calorieRingPlaceholder
                            .frame(width: 62, height: 62)
                    }

                    SkeletonBlock(width: nil, height: 18, cornerRadius: 9, palette: .accent, phase: shimmerPhase)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 10) {
                        macroPillSkeleton(width: 96)
                        macroPillSkeleton(width: 88)
                        macroPillSkeleton(width: 82)
                    }
                }
                .padding(18)
            }

            HStack(spacing: 12) {
                nutritionMetricCard(index: 0)
                nutritionMetricCard(index: 1)
            }

            SkeletonPanel(cornerRadius: 18) {
                VStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { index in
                        listRowSkeleton(index: index, showsIcon: true, showsTrailingCircle: false)

                        if index < 4 {
                            ItemListDivider()
                                .padding(.leading, 70)
                                .padding(.trailing, 14)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }

    private func segmentedControlSkeleton(widths: [CGFloat]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(widths.enumerated()), id: \.offset) { index, width in
                SkeletonBlock(
                    width: width,
                    height: 32,
                    cornerRadius: 16,
                    palette: index == 0 ? .accent : .surface,
                    phase: shimmerPhase
                )
            }

            Spacer(minLength: 0)
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppSkeletonPalette.surface.baseColor(for: colorScheme).opacity(0.54))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppSkeletonPalette.surface.strokeColor(for: colorScheme), lineWidth: 0.6)
                }
        }
    }

    private func listRowSkeleton(index: Int, showsIcon: Bool, showsTrailingCircle: Bool) -> some View {
        HStack(spacing: 14) {
            if showsIcon {
                SkeletonBlock(width: 42, height: 42, cornerRadius: 21, palette: index.isMultiple(of: 3) ? .accent : .surface, phase: shimmerPhase)
            }

            VStack(alignment: .leading, spacing: 7) {
                SkeletonBlock(width: index.isMultiple(of: 3) ? 136 : 190, height: 14, cornerRadius: 7, palette: .surface, phase: shimmerPhase)
                SkeletonBlock(width: index.isMultiple(of: 2) ? 84 : 116, height: 10, cornerRadius: 5, palette: .surface, phase: shimmerPhase)
            }

            Spacer(minLength: 0)

            if showsTrailingCircle {
                ZStack {
                    Circle()
                        .stroke(surfaceRingTrackColor, lineWidth: 4)
                    SkeletonBlock(width: 18, height: 10, cornerRadius: 5, palette: .surface, phase: shimmerPhase)
                }
                .frame(width: 42, height: 42)
            } else {
                SkeletonBlock(width: 10, height: 26, cornerRadius: 5, palette: .surface, phase: shimmerPhase)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recipeGridCard(index: Int, width: CGFloat) -> some View {
        SkeletonPanel(cornerRadius: 14) {
            ZStack(alignment: .bottomLeading) {
                SkeletonBlock(
                    width: width,
                    height: width * 1.28,
                    cornerRadius: 14,
                    palette: index.isMultiple(of: 4) ? .accent : .surface,
                    phase: shimmerPhase
                )

                VStack(alignment: .leading, spacing: 7) {
                    SkeletonBlock(width: min(width * 0.68, 96), height: 13, cornerRadius: 6.5, palette: .header, phase: shimmerPhase)
                    SkeletonBlock(width: min(width * 0.46, 62), height: 9, cornerRadius: 4.5, palette: .header, phase: shimmerPhase)
                }
                .padding(10)
            }
            .clipShape(.rect(cornerRadius: 14))
        }
    }

    private var nutritionDateStripe: some View {
        HStack(spacing: 0) {
            SkeletonBlock(width: 38, height: 42, cornerRadius: 10, palette: .surface, phase: shimmerPhase)
                .frame(width: 44)

            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    VStack(spacing: 4) {
                        SkeletonBlock(width: 12, height: 8, cornerRadius: 4, palette: .surface, phase: shimmerPhase)
                        SkeletonBlock(
                            width: 38,
                            height: 28,
                            cornerRadius: 10,
                            palette: index == 5 ? .accent : .surface,
                            phase: shimmerPhase
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: 74)
    }

    private func macroPillSkeleton(width: CGFloat) -> some View {
        SkeletonBlock(width: width, height: 34, cornerRadius: 17, palette: .surface, phase: shimmerPhase)
    }

    private func nutritionMetricCard(index: Int) -> some View {
        SkeletonPanel(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock(width: index == 0 ? 76 : 88, height: 13, cornerRadius: 6.5, palette: .surface, phase: shimmerPhase)
                SkeletonBlock(width: 54, height: 24, cornerRadius: 12, palette: .accent, phase: shimmerPhase)
                SkeletonBlock(width: 112, height: 10, cornerRadius: 5, palette: .surface, phase: shimmerPhase)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .frame(height: 108)
    }

    @ViewBuilder
    private var actionDeck: some View {
        #if os(macOS)
        macActionDeck
        #else
        iosActionDeck
        #endif
    }

    #if os(macOS)
    private var macActionDeck: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 12
            let width = geo.size.width
            let trailingColumnWidth = min(max(width * 0.36, 250), 330)
            let featuredHeight: CGFloat = 232
            let stackedHeight: CGFloat = (featuredHeight - spacing) / 2
            let quickTileHeight: CGFloat = 76

            VStack(alignment: .leading, spacing: spacing) {
                HStack(alignment: .top, spacing: spacing) {
                    featuredShortcutTile()
                        .frame(maxWidth: .infinity, minHeight: featuredHeight, maxHeight: featuredHeight)

                    VStack(spacing: spacing) {
                        wideShortcutTile()
                            .frame(height: stackedHeight)

                        wideShortcutTile(titleWidth: 68, subtitleWidth: 84, imageWidth: 82, imageHeight: 50, imageOffset: CGSize(width: 50, height: 10))
                            .frame(height: stackedHeight)
                    }
                    .frame(width: trailingColumnWidth)
                }

                HStack(alignment: .top, spacing: spacing) {
                    compactShortcutTile(labelWidth: 54, imageSize: 44, tileHeight: quickTileHeight)
                    compactShortcutTile(labelWidth: 50, imageSize: 48, tileHeight: quickTileHeight)
                    compactShortcutTile(labelWidth: 52, imageSize: 46, tileHeight: quickTileHeight)
                    compactShortcutTile(labelWidth: 50, imageSize: 44, tileHeight: quickTileHeight)
                }
                .frame(height: quickTileHeight + 26)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 338)
        .padding(.bottom, 12)
    }
    #else
    private var iosActionDeck: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geo in
                let spacing = homeShortcutSpacing
                let smallSide = homeShortcutSmallSide(for: geo.size.width)
                let topSide = smallSide * 2 + spacing

                VStack(spacing: spacing) {
                    HStack(spacing: spacing) {
                        featuredShortcutTile()
                            .frame(width: topSide, height: topSide)

                        VStack(spacing: spacing) {
                            wideShortcutTile()
                                .frame(width: topSide, height: smallSide)

                            wideShortcutTile(titleWidth: 68, subtitleWidth: 84, imageWidth: 82, imageHeight: 50, imageOffset: CGSize(width: 88, height: 18))
                                .frame(width: topSide, height: smallSide)
                        }
                        .frame(width: topSide, height: topSide)
                    }

                    HStack(spacing: spacing) {
                        compactShortcutTile(labelWidth: 54, imageSize: 42, tileHeight: smallSide)
                        compactShortcutTile(labelWidth: 50, imageSize: 50, tileHeight: smallSide)
                        compactShortcutTile(labelWidth: 52, imageSize: 46, tileHeight: smallSide)
                        compactShortcutTile(labelWidth: 50, imageSize: 44, tileHeight: smallSide)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: homeShortcutDeckHeight(for: shortcutDeckWidth))
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: LaunchSkeletonDeckWidthKey.self, value: proxy.size.width)
                }
            }
            .onPreferenceChange(LaunchSkeletonDeckWidthKey.self) { newWidth in
                shortcutDeckWidth = newWidth
            }
            .padding(.bottom, 40)
        }
    }
    #endif

    private var pendingNutritionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(titleWidth: 176, countWidth: 34)

            SkeletonPanel(cornerRadius: 18) {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        pendingNutritionRow

                        if index < 2 {
                            ItemListDivider()
                                .padding(.horizontal, 14)
                        }
                    }
                }
            }
        }
    }

    private var expiringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(titleWidth: 146, countWidth: 32)

            SkeletonPanel(cornerRadius: 18) {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        expiringRow

                        if index < 2 {
                            ItemListDivider()
                                .padding(.horizontal, 14)
                        }
                    }
                }
            }
        }
    }

    private var suggestedRecipesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(titleWidth: 154, countWidth: 34)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chipSkeleton(width: 84, palette: .accent)
                    chipSkeleton(width: 62)
                    chipSkeleton(width: 76)
                    chipSkeleton(width: 58)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        recipeSuggestionCard
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func sectionHeader(titleWidth: CGFloat, countWidth: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 6) {
                SkeletonBlock(width: titleWidth, height: 18, cornerRadius: 9, palette: .surface, phase: shimmerPhase)
                SkeletonBlock(width: 18, height: 18, cornerRadius: 9, palette: .surface, phase: shimmerPhase)
            }

            Spacer(minLength: 0)

            SkeletonBlock(width: countWidth, height: 26, cornerRadius: 13, palette: .surface, phase: shimmerPhase)
        }
    }

    private var pendingNutritionRow: some View {
        HStack(spacing: 12) {
            miniRingPlaceholder

            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(width: 106, height: 14, cornerRadius: 7, palette: .surface, phase: shimmerPhase)
                SkeletonBlock(width: 148, height: 12, cornerRadius: 6, palette: .surface, phase: shimmerPhase)
            }

            Spacer(minLength: 0)

            SkeletonBlock(width: 10, height: 14, cornerRadius: 5, palette: .surface, phase: shimmerPhase)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var miniRingPlaceholder: some View {
        ZStack {
            Circle()
                .stroke(surfaceRingTrackColor, lineWidth: 3)

            Circle()
                .trim(from: 0, to: 0.62)
                .stroke(PageTheme.nutrients.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            SkeletonBlock(width: 14, height: 8, cornerRadius: 4, palette: .surface, phase: shimmerPhase)
        }
        .frame(width: 34, height: 34)
    }

    private var skeletonContentBackground: Color {
        colorScheme == .dark ? appPrimaryBackground : Color.white
    }

    private var headerRingTrackColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.12)
    }

    private var headerRingProgressColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.24)
    }

    private var surfaceRingTrackColor: Color {
        colorScheme == .dark
            ? Color.secondary.opacity(0.18)
            : Color.black.opacity(0.10)
    }

    private var expiringRow: some View {
        HStack(spacing: 12) {
            SkeletonBlock(width: 28, height: 28, cornerRadius: 14, palette: .accent, phase: shimmerPhase)

            VStack(alignment: .leading, spacing: 5) {
                SkeletonBlock(width: 118, height: 14, cornerRadius: 7, palette: .surface, phase: shimmerPhase)
                SkeletonBlock(width: 92, height: 11, cornerRadius: 5.5, palette: .surface, phase: shimmerPhase)
            }

            Spacer(minLength: 0)

            SkeletonBlock(width: 46, height: 12, cornerRadius: 6, palette: .surface, phase: shimmerPhase)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var recipeSuggestionCard: some View {
        SkeletonPanel(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    SkeletonBlock(width: 210, height: 118, cornerRadius: 16, palette: .accent, phase: shimmerPhase)

                    SkeletonBlock(width: 46, height: 22, cornerRadius: 11, palette: .header, phase: shimmerPhase)
                        .padding(10)
                }

                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBlock(width: 132, height: 14, cornerRadius: 7, palette: .surface, phase: shimmerPhase)
                    SkeletonBlock(width: 164, height: 11, cornerRadius: 5.5, palette: .surface, phase: shimmerPhase)
                }
            }
            .frame(width: 210, alignment: .leading)
            .padding(12)
        }
    }

    private func featuredShortcutTile() -> some View {
        shortcutTile(
            titleWidth: 118,
            subtitleWidth: 134,
            imageWidth: 114,
            imageHeight: 114,
            imageOffset: CGSize(width: 24, height: 24),
            textAlignment: .topLeading,
            textPadding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
        )
    }

    private func wideShortcutTile(
        titleWidth: CGFloat = 74,
        subtitleWidth: CGFloat = 88,
        imageWidth: CGFloat = 96,
        imageHeight: CGFloat = 56,
        imageOffset: CGSize = CGSize(width: 74, height: 20)
    ) -> some View {
        shortcutTile(
            titleWidth: titleWidth,
            subtitleWidth: subtitleWidth,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            imageOffset: imageOffset,
            textAlignment: .bottomLeading,
            textPadding: EdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 16)
        )
    }

    private func shortcutTile(
        titleWidth: CGFloat,
        subtitleWidth: CGFloat,
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        imageOffset: CGSize,
        textAlignment: Alignment,
        textPadding: EdgeInsets
    ) -> some View {
        SkeletonPanel(cornerRadius: 16) {
            ZStack {
                SkeletonBlock(
                    width: imageWidth,
                    height: imageHeight,
                    cornerRadius: min(imageWidth, imageHeight) * 0.3,
                    palette: .accent,
                    phase: shimmerPhase
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: imageOffset.width >= 0 ? .bottomTrailing : .bottomLeading)
                .offset(imageOffset)

                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBlock(width: titleWidth, height: 18, cornerRadius: 9, palette: .surface, phase: shimmerPhase)
                    SkeletonBlock(width: subtitleWidth, height: 11, cornerRadius: 5.5, palette: .surface, phase: shimmerPhase)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: textAlignment)
                .padding(textPadding)
            }
            .clipShape(.rect(cornerRadius: 16))
        }
    }

    private func compactShortcutTile(labelWidth: CGFloat, imageSize: CGFloat, tileHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            SkeletonPanel(cornerRadius: 16) {
                ZStack {
                    SkeletonBlock(
                        width: imageSize,
                        height: imageSize,
                        cornerRadius: imageSize * 0.28,
                        palette: .accent,
                        phase: shimmerPhase
                    )

                    VStack {
                        HStack {
                            Spacer()
                            SkeletonBlock(width: 22, height: 22, cornerRadius: 11, palette: .surface, phase: shimmerPhase)
                                .padding(6)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .clipShape(.rect(cornerRadius: 16))
            }
            .frame(maxWidth: .infinity)
            .frame(height: tileHeight)

            SkeletonBlock(width: labelWidth, height: 11, cornerRadius: 5.5, palette: .surface, phase: shimmerPhase)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func chipSkeleton(width: CGFloat, palette: LaunchSkeletonPalette = .surface) -> some View {
        SkeletonBlock(width: width, height: 30, cornerRadius: 15, palette: palette, phase: shimmerPhase)
    }

    private var homeShortcutSpacing: CGFloat {
        8
    }

    private func homeShortcutSmallSide(for width: CGFloat) -> CGFloat {
        guard width > 0 else { return 72 }
        return max((width - homeShortcutSpacing * 3) / 4, 0)
    }

    private func homeShortcutDeckHeight(for width: CGFloat) -> CGFloat {
        let smallSide = homeShortcutSmallSide(for: width)
        return smallSide * 3 + homeShortcutSpacing * 2 + 22
    }

    private func startShimmer() {
        shimmerPhase = 0
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
            shimmerPhase = 1
        }
    }
}

private struct SkeletonPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(cornerRadius: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(panelFillColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(panelBorderColor, lineWidth: 0.6)
                    }
            }
    }

    private var panelBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04)
    }

    private var panelFillColor: Color {
        colorScheme == .dark
            ? neutralSurfaceColor
            : Color(red: 0.94, green: 0.94, blue: 0.95)
    }
}

private struct SkeletonBlock: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat
    let palette: LaunchSkeletonPalette
    let phase: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(palette.baseColor(for: colorScheme))
            .overlay {
                GeometryReader { proxy in
                    let sweepWidth = max(proxy.size.width * 0.7, 48)
                    let travel = proxy.size.width + sweepWidth * 2

                    LinearGradient(
                        colors: [
                            palette.highlightColor(for: colorScheme).opacity(0),
                            palette.highlightColor(for: colorScheme),
                            palette.highlightColor(for: colorScheme).opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: sweepWidth, height: proxy.size.height * 1.8)
                    .rotationEffect(.degrees(18))
                    .offset(x: -sweepWidth + phase * travel)
                    .blendMode(.screen)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(palette.strokeColor(for: colorScheme), lineWidth: 0.6)
            }
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

private typealias LaunchSkeletonPalette = AppSkeletonPalette

private struct LaunchSkeletonDeckWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#if os(iOS)
private struct LaunchSkeletonStatusBarModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background {
            StatusBarStyleView(style: colorScheme == .dark ? .lightContent : .darkContent)
                .frame(width: 0, height: 0)
        }
    }
}

private extension View {
    func launchSkeletonStatusBar() -> some View {
        modifier(LaunchSkeletonStatusBarModifier())
    }
}
#endif

#Preview {
    SplashView()
}
