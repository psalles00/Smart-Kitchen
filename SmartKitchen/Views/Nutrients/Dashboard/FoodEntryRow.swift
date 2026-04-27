import SwiftUI
import SwiftData

/// Linha compacta mostrando uma `FoodEntry` na seção de refeição do dashboard.
struct FoodEntryRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                    Text("·")
                    Text("P \(Int(entry.proteinG))g")
                    Text("C \(Int(entry.carbsG))g")
                    Text("G \(Int(entry.fatG))g")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

            Spacer()

            Text("\(entry.calories)")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(PageTheme.nutrients.accentColor)
            + Text(" kcal")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .contentShape(.rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let filename = entry.imageFilename,
           let img = FoodImageStore.shared.loadImage(filename: filename) {
            Image(platformImage: img)
                .resizable()
                .scaledToFill()
        } else if let emoji = entry.emoji, !emoji.isEmpty {
            ZStack {
                Rectangle()
                    .fill(PageTheme.nutrients.cardGradient)
                Text(emoji).font(.title2)
            }
        } else {
            ZStack {
                Rectangle()
                    .fill(PageTheme.nutrients.cardGradient)
                Image(systemName: entry.mealType.icon)
                    .foregroundStyle(.white)
            }
        }
    }
}
