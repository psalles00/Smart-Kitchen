import SwiftUI

/// A standalone section for editing a recipe's utensils list.
/// Extracted to its own View to avoid iOS 26 Form/Table overload ambiguity.
struct RecipeUtensilsEditor: View {
    @Binding var utensilNames: [IdentifiedUtensil]
    var onIconTapped: (UUID) -> Void = { _ in }

    var body: some View {
        Section {
            ForEach($utensilNames) { $utensil in
                VStack(alignment: .leading, spacing: 8) {
                    ItemSearchField(
                        text: $utensil.name,
                        placeholder: "Utensílio",
                        iconFileName: utensil.iconName,
                        fallbackSymbol: "fork.knife",
                        showsLeadingIcon: true,
                        onIconTapped: { onIconTapped(utensil.id) }
                    ) { entry in
                        utensil.name = entry.preferredTitle(matching: utensil.name)
                        utensil.category = entry.categoria
                        utensil.iconName = entry.nomeDoArquivo
                    }
                }
                .padding(.trailing, 36)
                .overlay(alignment: .topTrailing) {
                    Button {
                        utensilNames.removeAll { $0.id == utensil.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(.vertical, 4)
            }

            Button("Adicionar Utensílio", systemImage: "plus.circle") {
                utensilNames.append(IdentifiedUtensil())
            }
        } header: {
            Text("Utensílios")
        }
    }
}
