import SwiftUI
import SwiftData

/// Shows a list of past AI conversations, sorted by most recent.
struct ConversationHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatConversation.updatedAt, order: .reverse) private var conversations: [ChatConversation]
    @State private var activeSwipeConversationID: UUID?

    let showsHeader: Bool
    let topPinnedInset: CGFloat
    @Binding var isScrollAtTop: Bool
    let onSelect: (UUID) -> Void
    let onDismiss: () -> Void

    private var scrollTopThreshold: CGFloat {
        let topPadding = showsHeader ? 8 : topPinnedInset + 2
        return AssistantScrollMetrics.topThreshold(forTopPadding: topPadding)
    }

    init(
        showsHeader: Bool = true,
        topPinnedInset: CGFloat = 0,
        isScrollAtTop: Binding<Bool> = .constant(true),
        onSelect: @escaping (UUID) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.showsHeader = showsHeader
        self.topPinnedInset = topPinnedInset
        self._isScrollAtTop = isScrollAtTop
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
            }

            if conversations.isEmpty {
                emptyState
                    .onAppear {
                        isScrollAtTop = true
                    }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ScrollOffsetReader(coordinateSpace: "AssistantHistoryScroll")

                        ForEach(conversations) { conversation in
                            ConversationHistoryRow(
                                conversation: conversation,
                                formattedDate: formattedDate(conversation.updatedAt),
                                isDeleteRevealed: activeSwipeConversationID == conversation.id,
                                hasAnotherRowRevealed: activeSwipeConversationID != nil && activeSwipeConversationID != conversation.id,
                                onSelect: {
                                    onSelect(conversation.id)
                                },
                                onDelete: {
                                    deleteConversation(conversation)
                                },
                                onRevealDelete: { shouldReveal in
                                    withAnimation(.snappy(duration: 0.22)) {
                                        activeSwipeConversationID = shouldReveal ? conversation.id : nil
                                    }
                                },
                                onCloseOtherRows: closeAllSwipeActions
                            )
                        }
                    }
                    .padding(.top, showsHeader ? 8 : topPinnedInset + 2)
                    .padding(.bottom, 8)
                }
                .coordinateSpace(name: "AssistantHistoryScroll")
                .onScrollOffsetChange { offset in
                    isScrollAtTop = offset >= scrollTopThreshold
                }
                .onAppear {
                    isScrollAtTop = true
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            guard abs(value.translation.height) > abs(value.translation.width),
                                  activeSwipeConversationID != nil else { return }
                            closeAllSwipeActions()
                        }
                )
            }
        }
        .onChange(of: conversations.count) { _, _ in
            if let activeSwipeConversationID,
               !conversations.contains(where: { $0.id == activeSwipeConversationID }) {
                self.activeSwipeConversationID = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Text("Conversas anteriores")
                .font(.headline)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.quaternary)

            Text("Nenhuma conversa ainda")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, showsHeader ? 0 : topPinnedInset - 6)
    }

    private func deleteConversation(_ conversation: ChatConversation) {
        activeSwipeConversationID = nil
        let conversationID = conversation.id
        var messagesDescriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate<ChatMessage> { $0.conversationId == conversationID }
        )
        messagesDescriptor.fetchLimit = 500

        let linkedMessages = (try? modelContext.fetch(messagesDescriptor)) ?? []

        withAnimation(.snappy) {
            for message in linkedMessages {
                modelContext.delete(message)
            }
            modelContext.delete(conversation)
        }

        try? modelContext.save()
    }

    private func closeAllSwipeActions() {
        guard activeSwipeConversationID != nil else { return }
        withAnimation(.snappy(duration: 0.22)) {
            activeSwipeConversationID = nil
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Hoje, \(date.formatted(date: .omitted, time: .shortened))"
        } else if calendar.isDateInYesterday(date) {
            return "Ontem, \(date.formatted(date: .omitted, time: .shortened))"
        } else {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
    }
}

private struct ConversationHistoryRow: View {
    let conversation: ChatConversation
    let formattedDate: String
    let isDeleteRevealed: Bool
    let hasAnotherRowRevealed: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onRevealDelete: (Bool) -> Void
    let onCloseOtherRows: () -> Void

    @State private var rowOffset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    @State private var isDraggingHorizontally = false

    private let deleteActionWidth: CGFloat = 92
    private let fullSwipeDistance: CGFloat = 164
    private let revealThreshold: CGFloat = 44
    private let fullSwipeThreshold: CGFloat = 132

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteActionBackground

            rowContent
                .background(Rectangle().fill(.background))
                .offset(x: rowOffset)
                .contentShape(.rect)
                .onTapGesture {
                    handleTap()
                }
                .contextMenu {
                    Button("Abrir", systemImage: "bubble.left.and.text.bubble.right") {
                        handleOpenFromContextMenu()
                    }
                    Divider()
                    Button("Excluir", systemImage: "trash", role: .destructive) {
                        handleDelete()
                    }
                }
                .simultaneousGesture(swipeGesture)
        }
        .clipped()
        .onAppear {
            rowOffset = isDeleteRevealed ? -deleteActionWidth : 0
        }
        .onChange(of: isDeleteRevealed) { _, newValue in
            guard !isDraggingHorizontally else { return }
            withAnimation(.snappy(duration: 0.22)) {
                rowOffset = newValue ? -deleteActionWidth : 0
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 14))
                .foregroundStyle(.blue.opacity(0.7))
                .frame(width: 30, height: 30)
                .background(Color.blue.opacity(0.1), in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title ?? "Nova conversa")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var deleteActionBackground: some View {
        Rectangle()
            .fill(Color.red.gradient)
            .frame(width: max(-rowOffset, 0))
            .overlay(alignment: .trailing) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Excluir")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.trailing, 18)
                .opacity(deleteLabelOpacity)
            }
            .contentShape(.rect)
            .onTapGesture {
                guard isDeleteRevealed else { return }
                handleDelete()
            }
    }

    private var deleteLabelOpacity: Double {
        let progress = min(max((-rowOffset - 18) / 42, 0), 1)
        return Double(progress)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                if !isDraggingHorizontally {
                    isDraggingHorizontally = true
                    dragStartOffset = rowOffset
                    if hasAnotherRowRevealed {
                        onCloseOtherRows()
                        dragStartOffset = 0
                    }
                }

                rowOffset = clampedOffset(for: dragStartOffset + value.translation.width)
            }
            .onEnded { value in
                defer { isDraggingHorizontally = false }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                let predictedOffset = clampedOffset(for: dragStartOffset + value.predictedEndTranslation.width)
                if predictedOffset <= -fullSwipeThreshold {
                    handleDelete()
                    return
                }

                let shouldReveal = predictedOffset <= -revealThreshold
                withAnimation(.snappy(duration: 0.22)) {
                    rowOffset = shouldReveal ? -deleteActionWidth : 0
                }
                onRevealDelete(shouldReveal)
            }
    }

    private func clampedOffset(for proposedOffset: CGFloat) -> CGFloat {
        min(0, max(-fullSwipeDistance, proposedOffset))
    }

    private func handleTap() {
        if isDeleteRevealed {
            onRevealDelete(false)
            return
        }
        if hasAnotherRowRevealed {
            onCloseOtherRows()
            return
        }
        onSelect()
    }

    private func handleOpenFromContextMenu() {
        onCloseOtherRows()
        onSelect()
    }

    private func handleDelete() {
        onRevealDelete(false)
        onDelete()
    }
}
