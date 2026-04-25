import SwiftUI

// MARK: - Editor item model

/// Unified row for the ingredients editor. A single flat ordered list holds both
/// `section` rows (title + subtitle headers) and `ingredient` rows. Section
/// membership is derived from position: ingredients belong to the most recent
/// preceding section, or to the implicit top (unsectioned) group when there
/// is no section above them.
struct RecipeIngredientEditorItem: Identifiable {
    let id: UUID
    var isSection: Bool

    // Section fields
    var existingSectionID: UUID?
    var sectionTitle: String
    var sectionSubtitle: String

    // Ingredient fields
    var existingIngredientID: UUID?
    var name: String
    var quantity: String
    var unit: String
    var preparationState: String
    var category: String?
    var iconName: String?

    init(
        id: UUID = UUID(),
        isSection: Bool = false,
        existingSectionID: UUID? = nil,
        sectionTitle: String = "",
        sectionSubtitle: String = "",
        existingIngredientID: UUID? = nil,
        name: String = "",
        quantity: String = "",
        unit: String = "",
        preparationState: String = "",
        category: String? = nil,
        iconName: String? = nil
    ) {
        self.id = id
        self.isSection = isSection
        self.existingSectionID = existingSectionID
        self.sectionTitle = sectionTitle
        self.sectionSubtitle = sectionSubtitle
        self.existingIngredientID = existingIngredientID
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.preparationState = preparationState
        self.category = category
        self.iconName = iconName
    }

    var resolvedIconName: String? {
        if let iconName, !iconName.isEmpty {
            return iconName
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        return ItemDatabase.shared.preferredMatch(for: trimmedName)?.nomeDoArquivo
    }

    static func ingredient(
        existingID: UUID? = nil,
        name: String = "",
        quantity: String = "",
        unit: String = "",
        preparationState: String = "",
        category: String? = nil,
        iconName: String? = nil
    ) -> RecipeIngredientEditorItem {
        RecipeIngredientEditorItem(
            isSection: false,
            existingIngredientID: existingID,
            name: name,
            quantity: quantity,
            unit: unit,
            preparationState: preparationState,
            category: category,
            iconName: iconName
        )
    }

    static func section(
        existingID: UUID? = nil,
        title: String = "",
        subtitle: String = ""
    ) -> RecipeIngredientEditorItem {
        RecipeIngredientEditorItem(
            isSection: true,
            existingSectionID: existingID,
            sectionTitle: title,
            sectionSubtitle: subtitle
        )
    }
}

// MARK: - Editor section view

/// Reusable "Ingredientes" Section used by both `AddRecipeView` and
/// `EditRecipeView`. Renders a unified draggable list (ingredients + section
/// headers) with two equal-width action buttons at the bottom.
struct RecipeIngredientsSectionView: View {
    @Binding var items: [RecipeIngredientEditorItem]
    /// Callback invoked when the user taps an ingredient's icon (to open the
    /// icon picker). Receives the editor item id.
    var onIngredientIconTapped: (UUID) -> Void

    var body: some View {
        Section {
            ForEach($items) { $item in
                if item.isSection {
                    sectionHeaderRow(for: $item)
                } else {
                    ingredientRow(for: $item)
                }
            }
            .onDelete { offsets in
                items.remove(atOffsets: offsets)
            }
            .onMove { source, destination in
                items.move(fromOffsets: source, toOffset: destination)
            }

            HStack(spacing: 12) {
                Button {
                    items.append(.ingredient())
                } label: {
                    Label("Adicionar ingrediente", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    items.append(.section())
                } label: {
                    Label("Adicionar seção", systemImage: "text.line.first.and.arrowtriangle.forward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Ingredientes")
        } footer: {
            Text("Arraste para reordenar ou mover um ingrediente para outra seção.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Row builders

    @ViewBuilder
    private func sectionHeaderRow(for item: Binding<RecipeIngredientEditorItem>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                TextField("Título da seção (ex.: Para a massa)", text: item.sectionTitle)
                    .font(.subheadline.weight(.semibold))
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
            }
            TextField("Subtítulo ou nota (opcional)", text: item.sectionSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                #if os(iOS)
                .textInputAutocapitalization(.sentences)
                #endif
        }
        .padding(.vertical, 2)
        .listRowBackground(Color.accentColor.opacity(0.08))
    }

    @ViewBuilder
    private func ingredientRow(for item: Binding<RecipeIngredientEditorItem>) -> some View {
        #if os(macOS)
        HStack(spacing: 12) {
            ItemSearchField(
                text: item.name,
                placeholder: "",
                iconFileName: item.wrappedValue.resolvedIconName,
                fallbackSymbol: "leaf",
                showsLeadingIcon: true,
                onIconTapped: { onIngredientIconTapped(item.wrappedValue.id) }
            ) { entry in
                item.wrappedValue.name = entry.preferredTitle(matching: item.wrappedValue.name)
                item.wrappedValue.iconName = entry.nomeDoArquivo
                item.wrappedValue.category = entry.categoria
            }

            HStack(spacing: 4) {
                Text("Qt:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("0", text: item.quantity)
                    .frame(width: 50)
            }

            RecipeOptionMenuField(kind: .unit, selection: item.unit)
                .frame(minWidth: 120)

            RecipeOptionMenuField(kind: .state, selection: item.preparationState)
                .frame(minWidth: 140)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        #else
        VStack(alignment: .leading, spacing: 4) {
            ItemSearchField(
                text: item.name,
                placeholder: "Ingrediente",
                iconFileName: item.wrappedValue.resolvedIconName,
                fallbackSymbol: "leaf",
                showsLeadingIcon: true,
                onIconTapped: { onIngredientIconTapped(item.wrappedValue.id) }
            ) { entry in
                item.wrappedValue.name = entry.preferredTitle(matching: item.wrappedValue.name)
                item.wrappedValue.iconName = entry.nomeDoArquivo
                item.wrappedValue.category = entry.categoria
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    TextField("Qtd", text: item.quantity)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .frame(width: 44)

                    RecipeOptionMenuField(kind: .unit, selection: item.unit)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 28)

                RecipeOptionMenuField(kind: .state, selection: item.preparationState)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 1)
        #endif
    }
}

// MARK: - Helpers

extension Array where Element == RecipeIngredientEditorItem {
    /// Builds the item list from an existing recipe's sections + ingredients,
    /// preserving the user's previous ordering.
    static func fromRecipe(
        sections: [RecipeIngredientSection],
        ingredients: [RecipeIngredient]
    ) -> [RecipeIngredientEditorItem] {
        let sortedSections = sections.sorted { $0.sortOrder < $1.sortOrder }
        let sortedIngredients = ingredients.sorted { $0.sortOrder < $1.sortOrder }

        var result: [RecipeIngredientEditorItem] = []

        // Unsectioned ingredients first (implicit top group).
        for ing in sortedIngredients where ing.sectionID == nil {
            result.append(
                .ingredient(
                    existingID: ing.id,
                    name: ing.name,
                    quantity: ing.quantity.map {
                        $0.truncatingRemainder(dividingBy: 1) == 0
                            ? String(format: "%.0f", $0)
                            : String(format: "%.1f", $0)
                    } ?? "",
                    unit: ing.unit,
                    preparationState: ing.preparationState,
                    category: ItemDatabase.shared.entry(forFilename: ing.iconName ?? "")?.categoria
                        ?? ItemDatabase.shared.preferredMatch(for: ing.name)?.categoria,
                    iconName: ing.iconName
                )
            )
        }

        for section in sortedSections {
            result.append(
                .section(
                    existingID: section.id,
                    title: section.title,
                    subtitle: section.subtitle
                )
            )
            let belonging = sortedIngredients.filter { $0.sectionID == section.id }
            for ing in belonging {
                result.append(
                    .ingredient(
                        existingID: ing.id,
                        name: ing.name,
                        quantity: ing.quantity.map {
                            $0.truncatingRemainder(dividingBy: 1) == 0
                                ? String(format: "%.0f", $0)
                                : String(format: "%.1f", $0)
                        } ?? "",
                        unit: ing.unit,
                        preparationState: ing.preparationState,
                        category: ItemDatabase.shared.entry(forFilename: ing.iconName ?? "")?.categoria
                            ?? ItemDatabase.shared.preferredMatch(for: ing.name)?.categoria,
                        iconName: ing.iconName
                    )
                )
            }
        }

        return result
    }
}

/// Output bundle for persisting the editor items into SwiftData.
struct RecipeIngredientEditorCommit {
    let sections: [RecipeIngredientSection]
    let ingredients: [RecipeIngredient]
}

/// Output bundle for persisting the editor items back into import drafts.
struct RecipeIngredientDraftCommit {
    let sections: [SectionDraft]
    let ingredients: [IngredientDraft]
}

extension Array where Element == RecipeIngredientEditorItem {
    /// Builds the item list from an import draft (sections + ingredient drafts).
    static func fromDrafts(
        sections: [SectionDraft],
        ingredients: [IngredientDraft]
    ) -> [RecipeIngredientEditorItem] {
        let sortedSections = sections.sorted { $0.sortOrder < $1.sortOrder }

        func formatQuantity(_ q: Double?) -> String {
            guard let q else { return "" }
            return q.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", q)
                : String(format: "%.1f", q)
        }

        var result: [RecipeIngredientEditorItem] = []

        for ing in ingredients where ing.sectionID == nil {
            result.append(
                .ingredient(
                    existingID: ing.id,
                    name: ing.name,
                    quantity: formatQuantity(ing.quantity),
                    unit: ing.unit,
                    preparationState: ing.preparationState,
                    category: nil,
                    iconName: ing.iconName
                )
            )
        }

        for section in sortedSections {
            result.append(
                .section(
                    existingID: section.id,
                    title: section.title,
                    subtitle: section.subtitle
                )
            )
            for ing in ingredients where ing.sectionID == section.id {
                result.append(
                    .ingredient(
                        existingID: ing.id,
                        name: ing.name,
                        quantity: formatQuantity(ing.quantity),
                        unit: ing.unit,
                        preparationState: ing.preparationState,
                        category: nil,
                        iconName: ing.iconName
                    )
                )
            }
        }
        return result
    }
}

enum RecipeIngredientEditorPersistence {
    /// Walks `items` in order, materializing `RecipeIngredientSection` + `RecipeIngredient`
    /// objects. Section membership is determined by position: each ingredient
    /// is attached to the most recent preceding section (or `nil` when there
    /// is none). Sort orders are assigned per-group (sections share one sort
    /// space; ingredients share another).
    static func commit(items: [RecipeIngredientEditorItem]) -> RecipeIngredientEditorCommit {
        var sections: [RecipeIngredientSection] = []
        var ingredients: [RecipeIngredient] = []
        var currentSectionID: UUID? = nil
        var sectionIndex = 0
        var ingredientIndex = 0

        for item in items {
            if item.isSection {
                let trimmedTitle = item.sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedSubtitle = item.sectionSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                // Skip entirely-empty sections (no title AND no subtitle). They
                // provide no grouping value and would otherwise appear as
                // ghost headers after save.
                if trimmedTitle.isEmpty && trimmedSubtitle.isEmpty {
                    // Reset current section so ingredients below fall back to unsectioned
                    // (matches the visual expectation: an empty header is dropped).
                    currentSectionID = nil
                    continue
                }
                let sectionID = item.existingSectionID ?? UUID()
                let section = RecipeIngredientSection(
                    title: trimmedTitle,
                    subtitle: trimmedSubtitle,
                    sortOrder: sectionIndex,
                    id: sectionID
                )
                sections.append(section)
                currentSectionID = sectionID
                sectionIndex += 1
            } else {
                let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let ingredient = RecipeIngredient(
                    name: trimmed,
                    quantity: Double(item.quantity.replacingOccurrences(of: ",", with: ".")),
                    unit: item.unit.trimmingCharacters(in: .whitespaces),
                    preparationState: item.preparationState.trimmingCharacters(in: .whitespacesAndNewlines),
                    iconName: item.iconName ?? ItemDatabase.shared.preferredMatch(for: trimmed)?.nomeDoArquivo,
                    sortOrder: ingredientIndex,
                    sectionID: currentSectionID
                )
                ingredients.append(ingredient)
                ingredientIndex += 1
            }
        }

        return RecipeIngredientEditorCommit(sections: sections, ingredients: ingredients)
    }

    /// Same logic but emits import-draft values instead of SwiftData models.
    static func commitToDrafts(items: [RecipeIngredientEditorItem]) -> RecipeIngredientDraftCommit {
        var sections: [SectionDraft] = []
        var ingredients: [IngredientDraft] = []
        var currentSectionID: UUID? = nil
        var sectionIndex = 0

        for item in items {
            if item.isSection {
                let trimmedTitle = item.sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedSubtitle = item.sectionSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedTitle.isEmpty && trimmedSubtitle.isEmpty {
                    currentSectionID = nil
                    continue
                }
                let sectionID = item.existingSectionID ?? UUID()
                sections.append(
                    SectionDraft(
                        id: sectionID,
                        title: trimmedTitle,
                        subtitle: trimmedSubtitle,
                        sortOrder: sectionIndex
                    )
                )
                currentSectionID = sectionID
                sectionIndex += 1
            } else {
                let trimmed = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                ingredients.append(
                    IngredientDraft(
                        id: item.existingIngredientID ?? UUID(),
                        name: trimmed,
                        quantity: Double(item.quantity.replacingOccurrences(of: ",", with: ".")),
                        unit: item.unit.trimmingCharacters(in: .whitespaces),
                        preparationState: item.preparationState.trimmingCharacters(in: .whitespacesAndNewlines),
                        iconName: item.iconName,
                        confidence: .high,
                        sectionID: currentSectionID
                    )
                )
            }
        }

        return RecipeIngredientDraftCommit(sections: sections, ingredients: ingredients)
    }
}
