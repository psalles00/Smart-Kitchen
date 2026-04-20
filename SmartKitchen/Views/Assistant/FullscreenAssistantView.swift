import SwiftUI

// MARK: - Fullscreen Assistant View

/// Full-screen page that hosts both the "Assistente" (search) and the
/// "Modo IA" (chat) experiences on iOS.
///
/// Presented as a ZStack overlay in ContentView (not fullScreenCover) so that
/// `matchedGeometryEffect` can morph the trigger pill into the search bar.
///
/// Background: LiquidGlass on iOS 26+, solid white/black on older iOS.
/// Dismiss: tap empty area, drag down, or close button.
struct FullscreenAssistantView: View {
    let namespace: Namespace.ID
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
    private let topPinnedInset: CGFloat = 92

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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            UnifiedSearchBar(state: searchBarState) { _ in }
                .padding(.vertical, 6)
                .matchedGeometryEffect(id: "assistantBar", in: namespace)
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
                guard value.translation.height > 0 else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
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
        ScrollView {
            VStack(spacing: 12) {
                Text("Adicione itens, busque na despensa ou pergunte à IA.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, topPinnedInset + 8)

                VStack(alignment: .leading, spacing: 10) {
                    idleActionRow(icon: "sparkles", iconColor: .purple, text: "Perguntar à IA") {
                        pendingOpenChat = true
                    }
                    idleActionRow(icon: "plus.circle.fill", iconColor: .green, text: "Adicionar item") {
                        onAction(.addItem(prefill: "", iconFileName: nil, category: nil))
                        searchBarState.selectResult()
                    }
                    idleActionRow(icon: "book.closed", iconColor: .orange, text: "Adicionar receita") {
                        onAction(.addRecipe(prefill: ""))
                        searchBarState.selectResult()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
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
                .frame(height: 38)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(colorScheme == .dark ? 0.92 : 1), location: 0),
                            .init(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.65), location: 0.45),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .allowsHitTesting(false)
        }
    }

    private func idleActionRow(icon: String, iconColor: Color, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 36, height: 36)
                    .background(iconColor.opacity(0.12), in: .rect(cornerRadius: 10))

                Text(text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Background

    @ViewBuilder
    private var pageBackground: some View {
        Rectangle()
            .fill(Color.white)
    }
}
