import SwiftUI

struct CategoryIconView: View {
    let categoryName: String
    var size: CGFloat = 24
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
    var iconSize: CGFloat = 18
    var spacing: CGFloat = 8
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

struct CategorySelectionView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let categories: [CategoryDatabaseEntry]
    @Binding var selection: String

    var body: some View {
        List {
            ForEach(Array(categories.enumerated()), id: \.element.id) { _, category in
                Button {
                    selection = category.name
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        CategoryIconView(categoryName: category.name, size: 24)

                        Text(category.name)
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        Spacer(minLength: 12)

                        if selection == category.name {
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(minHeight: 40, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct CategorySelectionRow: View {
    let title: String
    let categories: [CategoryDatabaseEntry]
    @Binding var selection: String
    var iconSize: CGFloat = 16
    var spacing: CGFloat = 6
    var font: Font = .footnote

    #if os(macOS)
    @State private var showCategorySelection = false
    #endif

    var body: some View {
        #if os(iOS)
        NavigationLink {
            CategorySelectionView(
                title: title,
                categories: categories,
                selection: $selection
            )
        } label: {
            rowLabel
        }
        #else
        Button {
            showCategorySelection = true
        } label: {
            rowLabel
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showCategorySelection) {
            NavigationStack {
                CategorySelectionView(
                    title: title,
                    categories: categories,
                    selection: $selection
                )
            }
            .frame(minWidth: 320, minHeight: 420)
            .forceLightStatusBar()
        }
        #endif
    }

    private var rowLabel: some View {
        HStack {
            Text(title)
            Spacer()
            CategoryLabelView(
                categoryName: selection,
                iconSize: iconSize,
                spacing: spacing,
                font: font
            )
            #if os(macOS)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
            #endif
        }
        .contentShape(Rectangle())
    }
}
