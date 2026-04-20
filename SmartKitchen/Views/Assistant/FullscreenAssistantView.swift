import SwiftUI

// MARK: - Fullscreen Assistant View

/// Full-screen page that hosts both the "Assistente" (search) and the
/// "Modo IA" (chat) experiences on iOS.
///
/// Presented as a ZStack overlay in ContentView so the persistent search bar
/// remains mounted and focused while the assistant expands.
///
/// Background: LiquidGlass on iOS 26+, solid white/black on older iOS.
/// Dismiss: tap empty area, drag down, or close button.
struct FullscreenAssistantView: View {
    @ObservedObject var searchBarState: SearchBarState
    @ObservedObject var searchService: UniversalSearchService
    @Environment(\.colorScheme) private var colorScheme

    let onAction: (CommandBarAction) -> Void

    @Binding var pendingChatQuery: String?
    @Binding var pendingOpenChat: Bool
    @Binding var pendingNewConversation: Bool
    @Binding var pendingShowHistory: Bool

    // Drag-to-dismiss
    @State private var dragOffset: CGFloat = 0
    @State private var contentOpacity: Double = 0.88
    @State private var isScrollableContentAtTop: Bool = true
    // Snapshot of scroll-at-top status captured at the moment a drag begins.
    // nil means the current drag hasn't started yet.
    @State private var dragStartedAtTop: Bool? = nil
    private let topPinnedInset: CGFloat = 72

    var body: some View {
        ZStack {
            // Tappable background — dismiss on tap
            pageBackground
                .ignoresSafeArea()
                .onTapGesture { searchBarState.dismiss() }

            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    pinnedHeader
                }
            .offset(y: max(dragOffset, 0))
            .opacity(contentOpacity)
        }
        .simultaneousGesture(dismissDragGesture)
        .onAppear {
            withAnimation(.smooth(duration: 0.12)) {
                contentOpacity = 1
            }
        }
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                // A drag that starts while content is scrolled must never switch
                // into dismiss mode mid-gesture just because it later reaches top.
                if dragStartedAtTop == nil {
                    dragStartedAtTop = isScrollableContentAtTop
                }
                guard value.translation.height > 0, dragStartedAtTop == true else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let startedAtTop = dragStartedAtTop ?? isScrollableContentAtTop
                dragStartedAtTop = nil

                guard startedAtTop else {
                    withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
                        dragOffset = 0
                    }
                    return
                }

                if value.translation.height > 120 || value.predictedEndTranslation.height > 300 {
                    searchBarState.dismiss()
                } else {
                    withAnimation(.snappy(duration: 0.2, extraBounce: 0.02)) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center) {
            Text(searchBarState.mode == .aiChat ? "Modo IA" : "Assistente")
                .font(.pageTitle)
                .foregroundStyle(Color.primary)

            Spacer()

            if searchBarState.mode == .aiChat {
                Button {
                    pendingNewConversation = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Button {
                    pendingShowHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            Button {
                searchBarState.dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        let hasText = !searchBarState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let showResults = hasText || searchBarState.mode == .aiChat || pendingOpenChat || pendingChatQuery != nil

        if showResults {
            InlineSearchResultsView(
                searchBarState: searchBarState,
                searchService: searchService,
                onAction: onAction,
                topPinnedInset: topPinnedInset,
                isScrollAtTop: $isScrollableContentAtTop,
                pendingChatQuery: $pendingChatQuery,
                pendingOpenChat: $pendingOpenChat,
                pendingNewConversation: $pendingNewConversation,
                pendingShowHistory: $pendingShowHistory
            )
        } else {
            idleActionButtons
        }
    }

    // MARK: - Idle Action Buttons (nothing typed)

    private var idleActionButtons: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    ScrollOffsetReader(coordinateSpace: "AssistantIdleScroll")

                    Text("Adicione itens, busque na despensa ou pergunte à IA.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, topPinnedInset)

                    VStack(alignment: .leading, spacing: 10) {
                        CommandBarHelpers.fullWidthActionButton(
                            title: "Perguntar à IA",
                            icon: "sparkles",
                            tint: .blue,
                            imageName: "modo ia",
                            imageHeight: 84,
                            imageOffset: CGSize(width: 8, height: 18)
                        ) {
                            pendingOpenChat = true
                        }

                        CommandBarHelpers.fullWidthActionButton(
                            title: "Adicionar item",
                            icon: "plus.circle.fill",
                            tint: .orange,
                            imageName: "despensa",
                            imageHeight: 78,
                            imageOffset: CGSize(width: 6, height: 21)
                        ) {
                            onAction(.addItem(prefill: "", iconFileName: nil, category: nil))
                            searchBarState.selectResult()
                        }

                        CommandBarHelpers.fullWidthActionButton(
                            title: "Adicionar receita",
                            icon: "book.badge.plus",
                            tint: .red,
                            imageName: "receitas",
                            imageHeight: 78,
                            imageOffset: CGSize(width: 6, height: 21)
                        ) {
                            onAction(.addRecipe(prefill: ""))
                            searchBarState.selectResult()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Spacer(minLength: 0)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            searchBarState.dismiss()
                        }
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                .padding(.bottom, 20)
            }
            .coordinateSpace(name: "AssistantIdleScroll")
            .onScrollOffsetChange { offset in
                isScrollableContentAtTop = offset >= -10
            }
            .onAppear {
                isScrollableContentAtTop = true
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var pinnedHeader: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
                .highPriorityGesture(dismissDragGesture)
                .background(Color.white, ignoresSafeAreaEdges: .top)

            Rectangle()
                .fill(.bar)
                .frame(height: 28)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(colorScheme == .dark ? 0.92 : 1), location: 0),
                            .init(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.65), location: 0.34),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .allowsHitTesting(false)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var pageBackground: some View {
        Rectangle()
            .fill(Color.white)
    }
}
