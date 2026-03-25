import SwiftUI

struct ListsInfoContent: View {
    let totalTasks: Int = 12
    let urgentCount: Int = 2
    let highCount: Int = 4
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Suas Tarefas")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("\(totalTasks) pendentes no total")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
            }
            Spacer()
            HStack(spacing: 12) {
                if urgentCount > 0 {
                    PriorityBadge(count: urgentCount, color: .red, label: "Urgentes")
                }
                if highCount > 0 {
                    PriorityBadge(count: highCount, color: .orange, label: "Alta")
                }
            }
        }
    }
}

private struct PriorityBadge: View {
    let count: Int
    let color: Color
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.75))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.3))
        )
    }
}
