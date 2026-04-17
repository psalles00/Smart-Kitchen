import SwiftUI
import SwiftData

struct HomeInfoContent: View {
    @Query(sort: \PantryItem.name) private var pantryItems: [PantryItem]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(sort: \GroceryItem.name) private var groceryItems: [GroceryItem]

    private var expiringCount: Int {
        let limit = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        return pantryItems.filter { ($0.expirationDate ?? .distantFuture) <= limit }.count
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Visão geral")
                    .font(.headline)
                    .foregroundColor(.white)

                HStack(spacing: 8) {
                    Label("\(pantryItems.count) na despensa", systemImage: "refrigerator")
                    Label("\(groceryItems.count) no mercado", systemImage: "cart")
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
            }
        }
    }
}
