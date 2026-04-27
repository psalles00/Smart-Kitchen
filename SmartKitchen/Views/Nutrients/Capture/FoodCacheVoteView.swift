import SwiftUI

/// Compact thumbs-up / thumbs-down feedback for cached food entries.
///
/// Renders nothing when `foodIDs` is empty (legacy paths or cache disabled).
/// After a vote is cast for an entry, it is remembered locally so the user
/// is not prompted again for the same item from the same device.
@MainActor
struct FoodCacheVoteView: View {
    let foodIDs: [UUID]

    @State private var voted: Bool = false
    @State private var sending: Bool = false
    @State private var lastVote: FoodCache.Vote? = nil

    private var alreadyVoted: Bool {
        let cache = FoodCache.shared
        return foodIDs.contains { cache.recordedVote(for: $0) != nil }
    }

    var body: some View {
        if foodIDs.isEmpty || alreadyVoted || voted {
            if voted, let lastVote {
                Label(
                    lastVote == .up ? "Obrigado pelo feedback" : "Vamos buscar de novo",
                    systemImage: lastVote == .up ? "checkmark.circle.fill" : "arrow.clockwise.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                EmptyView()
            }
        } else {
            HStack(spacing: 12) {
                Text("Estes dados parecem corretos?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    cast(.up)
                } label: {
                    Image(systemName: "hand.thumbsup")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(sending)

                Button {
                    cast(.down)
                } label: {
                    Image(systemName: "hand.thumbsdown")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(sending)
            }
        }
    }

    private func cast(_ vote: FoodCache.Vote) {
        guard !sending else { return }
        sending = true
        let ids = foodIDs
        Task { @MainActor in
            for id in ids {
                do {
                    try await FoodCache.shared.vote(foodID: id, vote)
                    FoodCache.shared.rememberVote(vote, for: id)
                } catch {
                    // Silent — voting is best-effort.
                }
            }
            self.lastVote = vote
            self.voted = true
            self.sending = false
        }
    }
}
