import SwiftUI

/// A standalone section for editing a recipe's utensils list.
/// Extracted to its own View to avoid iOS 26 Form/Table overload ambiguity.
struct RecipeUtensilsEditor: View {
    @Binding var utensilNames: [IdentifiedUtensil]
    @Binding var newUtensilName: String

    var body: some View {
        Section {
            ForEach($utensilNames) { $utensil in
                HStack {
                    Text(utensil.name)
                    Spacer()
                    Button {
                        utensilNames.removeAll { $0.id == utensil.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                TextField("Nome do utensílio", text: $newUtensilName)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif

                Button {
                    let trimmed = newUtensilName.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    utensilNames.append(IdentifiedUtensil(name: trimmed))
                    newUtensilName = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newUtensilName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Utensílios")
        }
    }
}
