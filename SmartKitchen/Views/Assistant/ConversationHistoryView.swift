import SwiftUI
import SwiftData

/// Shows a list of past AI conversations, sorted by most recent.
struct ConversationHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatConversation.updatedAt, order: .reverse) private var conversations: [ChatConversation]

    let showsHeader: Bool
    let topPinnedInset: CGFloat
    @Binding var isScrollAtTop: Bool
    let onSelect: (UUID) -> Void
    let onDismiss: () -> Void

    private var scrollTopThreshold: CGFloat {
        let topPadding = showsHeader ? 8 : topPinnedInset + 2
        return topPadding - 10
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
                            conversationRow(conversation)
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

    private func conversationRow(_ conversation: ChatConversation) -> some View {
        Button {
            onSelect(conversation.id)
        } label: {
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

                    Text(formattedDate(conversation.updatedAt))
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
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
