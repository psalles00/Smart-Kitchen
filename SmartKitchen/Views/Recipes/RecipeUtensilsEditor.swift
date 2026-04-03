import SwiftUI

/// A standalone section for editing a recipe's utensils list.
/// Extracted to its own View to avoid iOS 26 Form/Table overload ambiguity.
struct RecipeUtensilsEditor: View {
    @Binding var utensilNames: [IdentifiedUtensil]
    @State private var activePicker: UtensilPickerTarget?

    var body: some View {
        Section {
            ForEach($utensilNames) { $utensil in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        ItemSearchField(
                            text: $utensil.name,
                            placeholder: "Utensílio",
                            iconFileName: utensil.iconName,
                            fallbackSymbol: "fork.knife",
                            showsLeadingIcon: true,
                            onIconTapped: { activePicker = UtensilPickerTarget(id: utensil.id) }
                        ) { entry in
                            utensil.name = entry.preferredTitle(matching: utensil.name)
                            utensil.category = entry.categoria
                            utensil.iconName = entry.nomeDoArquivo
                        }

                        if let category = utensil.category, !category.isEmpty {
                            Text(category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 50)
                        }
                    }

                    Button {
                        utensilNames.removeAll { $0.id == utensil.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                            .padding(.top, 6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }

            Button("Adicionar Utensílio", systemImage: "plus.circle") {
                utensilNames.append(IdentifiedUtensil())
            }
        } header: {
            Text("Utensílios")
        }
        .sheet(item: $activePicker) { target in
            ItemIconPickerView(
                initialQuery: utensilName(for: target.id),
                currentIconFileName: utensilIconName(for: target.id),
                fallbackSymbol: "fork.knife"
            ) { entry in
                applySelectedEntry(entry, to: target.id)
            }
        }
    }

    private func applySelectedEntry(_ entry: ItemEntry, to utensilID: UUID) {
        guard let index = utensilNames.firstIndex(where: { $0.id == utensilID }) else { return }
        utensilNames[index].name = entry.preferredTitle(matching: utensilNames[index].name)
        utensilNames[index].category = entry.categoria
        utensilNames[index].iconName = entry.nomeDoArquivo
    }

    private func utensilName(for utensilID: UUID) -> String {
        utensilNames.first(where: { $0.id == utensilID })?.name ?? ""
    }

    private func utensilIconName(for utensilID: UUID) -> String? {
        utensilNames.first(where: { $0.id == utensilID })?.iconName
    }
}

private struct UtensilPickerTarget: Identifiable {
    let id: UUID
}
