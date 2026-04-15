import SwiftUI
import SwiftData

/// Shows a list of past AI conversations, sorted by most recent.
struct ConversationHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatConversation.updatedAt, order: .reverse) private var conversations: [ChatConversation]

    let onSelect: (UUID) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            if conversations.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(conversations) { conversation in
                            conversationRow(conversation)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.bottom, 60)
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
