import SwiftUI
import SwiftData

struct HomeInfoContent: View {
    @Query(filter: #Predicate<UnifiedItem> { $0.isPantry }, sort: \UnifiedItem.name) private var pantryItems: [UnifiedItem]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(filter: #Predicate<UnifiedItem> { $0.isGrocery }, sort: \UnifiedItem.name) private var groceryItems: [UnifiedItem]

    private var expiringCount: Int {
        let limit = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        return pantryItems.filter { ($0.expirationDate ?? .distantFuture) <= limit }.count
    }

    private var todayString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt-BR")
        formatter.dateFormat = "EEEE, d 'de' MMMM"
        return formatter.string(from: .now).localizedCapitalized
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(todayString)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                HStack(spacing: 8) {
                    Label("\(pantryItems.count) na despensa", systemImage: "refrigerator")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Label("\(groceryItems.count) no mercado", systemImage: "cart")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(recipes.count)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text("receitas")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}
