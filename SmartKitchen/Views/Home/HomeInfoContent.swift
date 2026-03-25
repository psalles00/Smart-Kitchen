import SwiftUI

struct HomeInfoContent: View {
    let selectedDate: Date = Date()
    let tasksCount: Int = 6
    let eventsCount: Int = 3
    let completedCount: Int = 4
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "d 'de' MMMM 'de' yyyy"
        return formatter.string(from: selectedDate)
    }
    
    private var completionPercentage: Int {
        guard tasksCount > 0 else { return 0 }
        return Int((Double(completedCount) / Double(tasksCount)) * 100)
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate)
                    .font(.headline)
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    Label("\(tasksCount) tarefas", systemImage: "checkmark.circle")
                    Label("\(eventsCount) eventos", systemImage: "calendar")
                }
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
            }
            
            Spacer()
            
            if tasksCount > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(completionPercentage)%")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    Text("concluído")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
    }
}
