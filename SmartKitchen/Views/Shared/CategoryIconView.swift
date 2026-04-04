import SwiftUI

struct CategoryIconView: View {
    let categoryName: String
    var size: CGFloat = 18
    var showBalloon: Bool = false

    private var entry: CategoryDatabaseEntry? {
        CategoryDatabase.shared.entry(for: categoryName)
    }

    var body: some View {
        IconImage(
            name: "",
            iconFileName: entry?.iconFileName,
            fallbackSymbol: "square.grid.2x2",
            size: size,
            showBalloon: showBalloon
        )
    }
}

struct CategoryLabelView: View {
    let categoryName: String
    var iconSize: CGFloat = 14
    var spacing: CGFloat = 6
    var font: Font = .caption

    var body: some View {
        HStack(spacing: spacing) {
            CategoryIconView(categoryName: categoryName, size: iconSize)
            Text(categoryName)
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.vertical, 1)
    }
}
