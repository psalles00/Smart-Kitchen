import Foundation
import SwiftData
import SwiftUI

struct CategorySeedDefinition: Hashable {
    let name: String
    let iconName: String?
}

enum CategoryType: String, Codable, CaseIterable, Identifiable {
    case pantry
    case grocery
    case recipe
    case utensil

    var id: String { rawValue }

    var canonicalType: CategoryType {
        switch self {
        case .pantry, .grocery: .pantry
        case .recipe: .recipe
        case .utensil: .utensil
        }
    }

    var isListType: Bool {
        switch self {
        case .pantry, .grocery, .utensil: true
        case .recipe: false
        }
    }

    var displayName: LocalizedStringKey {
        switch self {
        case .pantry: "Despensa"
        case .grocery: "Mercado"
        case .recipe: "Receitas"
        case .utensil: "Utensílios"
        }
    }
}

@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var type: CategoryType = CategoryType.pantry
    var iconName: String? = nil
    var sortOrder: Int = 0

    init(name: String, type: CategoryType, iconName: String? = nil, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.iconName = iconName
        self.sortOrder = sortOrder
    }
}

@Model
final class DeletedDefaultCategory {
    var id: UUID = UUID()
    var name: String = ""
    var type: CategoryType = CategoryType.recipe

    init(name: String, type: CategoryType) {
        self.id = UUID()
        self.name = name
        self.type = type.canonicalType
    }
}

enum CategoryMutationError: LocalizedError {
    case invalidName
    case duplicateName
    case categoryNotFound

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Nome de categoria inválido."
        case .duplicateName:
            return "Essa categoria já existe."
        case .categoryNotFound:
            return "Categoria não encontrada."
        }
    }
}

enum CategoryDeletionStrategy {
    case reassign(toCategoryNamed: String?)
    case deleteRecipes
}

struct CategoryDeletionResult {
    let deletedName: String
    let reassignedName: String?
    let affectedEntityCount: Int
    let deletedRecipeCount: Int
}

enum CategoryMutationService {
    static func normalizedKey(for text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    static func matchesName(_ lhs: String, _ rhs: String) -> Bool {
        normalizedKey(for: lhs) == normalizedKey(for: rhs)
    }

    static func fetchCategories(of type: CategoryType, context: ModelContext) -> [Category] {
        let descriptor = FetchDescriptor<Category>(sortBy: [SortDescriptor(\.sortOrder)])
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.type == type.canonicalType }
    }

    static func fetchDeletedDefaultNames(of type: CategoryType, context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<DeletedDefaultCategory>()
        return Set(
            ((try? context.fetch(descriptor)) ?? [])
                .filter { $0.type == type.canonicalType }
                .map { normalizedKey(for: $0.name) }
        )
    }

    static func canonicalCategoryName(for proposedName: String, type: CategoryType, context: ModelContext) -> String? {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return fetchCategories(of: type, context: context)
            .first(where: { matchesName($0.name, trimmed) })?
            .name
    }

    static func defaultCategoryName(for type: CategoryType, context: ModelContext) -> String {
        let categories = fetchCategories(of: type, context: context)

        if let others = categories.first(where: { matchesName($0.name, "Outros") }) {
            return others.name
        }

        if let first = categories.first {
            return first.name
        }

        return ensureCategory(named: "Outros", type: type, context: context).name
    }

    static func defaultRecipeCategoryName(context: ModelContext) -> String {
        defaultCategoryName(for: .recipe, context: context)
    }

    static func normalizedRecipeCategories(from rawValue: String, context: ModelContext) -> [String] {
        let candidates = rawValue
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var uniqueKeys = Set<String>()
        var resolvedNames: [String] = []

        for candidate in candidates {
            let resolvedName = canonicalCategoryName(for: candidate, type: .recipe, context: context)
                ?? ensureCategory(named: candidate, type: .recipe, context: context).name
            let key = normalizedKey(for: resolvedName)
            guard uniqueKeys.insert(key).inserted else { continue }
            resolvedNames.append(resolvedName)
        }

        if resolvedNames.isEmpty {
            resolvedNames = [defaultRecipeCategoryName(context: context)]
        }

        return resolvedNames
    }

    static func normalizedRecipeCategoryString(from rawValue: String, context: ModelContext) -> String {
        normalizedRecipeCategories(from: rawValue, context: context).joined(separator: ", ")
    }

    @discardableResult
    static func ensureCategory(
        named proposedName: String,
        type: CategoryType,
        iconName: String? = nil,
        context: ModelContext
    ) -> Category {
        if let existingName = canonicalCategoryName(for: proposedName, type: type, context: context),
           let existingCategory = fetchCategories(of: type, context: context).first(where: { matchesName($0.name, existingName) }) {
            return existingCategory
        }

        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedType = type.canonicalType
        let categories = fetchCategories(of: resolvedType, context: context)
        let nextSortOrder = (categories.map(\.sortOrder).max() ?? -1) + 1
        let category = Category(
            name: trimmedName,
            type: resolvedType,
            iconName: iconName ?? defaultDefinition(named: trimmedName, type: resolvedType)?.iconName,
            sortOrder: nextSortOrder
        )
        context.insert(category)
        return category
    }

    @discardableResult
    static func createCategory(
        named proposedName: String,
        type: CategoryType,
        iconName: String? = nil,
        context: ModelContext
    ) throws -> Category {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw CategoryMutationError.invalidName
        }

        guard canonicalCategoryName(for: trimmedName, type: type, context: context) == nil else {
            throw CategoryMutationError.duplicateName
        }

        return ensureCategory(named: trimmedName, type: type, iconName: iconName, context: context)
    }

    @discardableResult
    static func renameCategory(
        named currentName: String,
        to newName: String,
        type: CategoryType,
        context: ModelContext
    ) throws -> Category {
        let categories = fetchCategories(of: type, context: context)
        guard let category = categories.first(where: { matchesName($0.name, currentName) }) else {
            throw CategoryMutationError.categoryNotFound
        }
        return try renameCategory(category, to: newName, context: context)
    }

    @discardableResult
    static func renameCategory(_ category: Category, to proposedName: String, context: ModelContext) throws -> Category {
        let trimmedName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw CategoryMutationError.invalidName
        }

        let resolvedType = category.type.canonicalType
        if let existing = fetchCategories(of: resolvedType, context: context).first(where: { matchesName($0.name, trimmedName) && $0.id != category.id }) {
            _ = existing
            throw CategoryMutationError.duplicateName
        }

        let previousName = category.name
        category.name = trimmedName
        if category.iconName == nil {
            category.iconName = defaultDefinition(named: trimmedName, type: resolvedType)?.iconName
        }
        reassignCategoryReferences(from: previousName, to: trimmedName, type: resolvedType, context: context)
        return category
    }

    static func moveCategory(named name: String, type: CategoryType, to requestedPosition: Int, context: ModelContext) throws -> Int {
        var categories = fetchCategories(of: type, context: context)
        guard let index = categories.firstIndex(where: { matchesName($0.name, name) }) else {
            throw CategoryMutationError.categoryNotFound
        }

        let safePosition = max(0, min(requestedPosition, categories.count - 1))
        let category = categories.remove(at: index)
        categories.insert(category, at: safePosition)

        for (sortOrder, item) in categories.enumerated() {
            item.sortOrder = sortOrder
        }

        return safePosition
    }

    static func moveCategories(of type: CategoryType, from source: IndexSet, to destination: Int, context: ModelContext) {
        var categories = fetchCategories(of: type, context: context)
        categories.move(fromOffsets: source, toOffset: destination)
        for (index, category) in categories.enumerated() {
            category.sortOrder = index
        }
    }

    static func deleteCategory(
        named name: String,
        type: CategoryType,
        strategy: CategoryDeletionStrategy,
        context: ModelContext
    ) throws -> CategoryDeletionResult {
        let categories = fetchCategories(of: type, context: context)
        guard let category = categories.first(where: { matchesName($0.name, name) }) else {
            throw CategoryMutationError.categoryNotFound
        }
        return try deleteCategory(category, strategy: strategy, context: context)
    }

    static func deleteCategory(
        _ category: Category,
        strategy: CategoryDeletionStrategy,
        context: ModelContext
    ) throws -> CategoryDeletionResult {
        let resolvedType = category.type.canonicalType
        let affectedEntities = referenceCount(for: category, context: context)
        var reassignedName: String?
        var deletedRecipeCount = 0

        switch strategy {
        case .reassign(let requestedTarget):
            if affectedEntities > 0 {
                let targetName: String
                if let requestedTarget,
                   !requestedTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !matchesName(requestedTarget, category.name) {
                    targetName = ensureCategory(named: requestedTarget, type: resolvedType, context: context).name
                } else {
                    targetName = fallbackCategoryName(for: resolvedType, excluding: category, context: context)
                }

                reassignCategoryReferences(from: category.name, to: targetName, type: resolvedType, context: context)
                reassignedName = targetName
            }

        case .deleteRecipes:
            guard resolvedType == .recipe else {
                break
            }

            deletedRecipeCount = deleteRecipes(in: category.name, context: context)
        }

        recordDeletedDefaultIfNeeded(named: category.name, type: resolvedType, context: context)
        context.delete(category)
        normalizeCategoryOrder(for: resolvedType, context: context)

        return CategoryDeletionResult(
            deletedName: category.name,
            reassignedName: reassignedName,
            affectedEntityCount: affectedEntities,
            deletedRecipeCount: deletedRecipeCount
        )
    }

    static func recipeCategoryPromptSection(context: ModelContext) -> String {
        let categories = fetchCategories(of: .recipe, context: context)
        if categories.isEmpty {
            return "## Cadernos de receitas\nNenhum caderno cadastrado. Se fizer sentido, você pode sugerir um novo caderno curto e natural em português."
        }

        let recipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        let lines = categories.map { category in
            let count = recipes.filter { recipe in
                recipe.categories.contains(where: { matchesName($0, category.name) })
            }.count
            let label = count == 1 ? "1 receita" : "\(count) receitas"
            return "- \(category.name) (\(label))"
        }

        return """
        ## Cadernos de receitas disponíveis
        Prefira usar estes nomes exatos ao classificar uma receita. Se nenhum servir claramente, proponha um nome curto e coerente.
        \(lines.joined(separator: "\n"))
        """
    }

    private static func normalizeCategoryOrder(for type: CategoryType, context: ModelContext) {
        for (index, category) in fetchCategories(of: type, context: context).enumerated() {
            category.sortOrder = index
        }
    }

    private static func defaultDefinition(named name: String, type: CategoryType) -> CategorySeedDefinition? {
        DataSeeder.defaultDefinitions(for: type)
            .first(where: { matchesName($0.name, name) })
    }

    private static func recordDeletedDefaultIfNeeded(named name: String, type: CategoryType, context: ModelContext) {
        guard defaultDefinition(named: name, type: type) != nil else { return }

        let deletedDefaults = fetchDeletedDefaultNames(of: type, context: context)
        let key = normalizedKey(for: name)
        guard !deletedDefaults.contains(key) else { return }

        context.insert(DeletedDefaultCategory(name: name, type: type))
    }

    private static func fallbackCategoryName(for type: CategoryType, excluding category: Category, context: ModelContext) -> String {
        let remainingCategories = fetchCategories(of: type, context: context).filter { $0.id != category.id }

        if let others = remainingCategories.first(where: { matchesName($0.name, "Outros") }) {
            return others.name
        }

        if let first = remainingCategories.first {
            return first.name
        }

        return ensureCategory(named: "Outros", type: type, context: context).name
    }

    private static func referenceCount(for category: Category, context: ModelContext) -> Int {
        switch category.type.canonicalType {
        case .pantry, .grocery:
            let items = (try? context.fetch(FetchDescriptor<UnifiedItem>())) ?? []
            return items.filter { ($0.isPantry || $0.isGrocery) && matchesName($0.category, category.name) }.count

        case .recipe:
            let recipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
            return recipes.filter { recipe in
                recipe.categories.contains(where: { matchesName($0, category.name) })
            }.count

        case .utensil:
            let items = (try? context.fetch(FetchDescriptor<UnifiedItem>())) ?? []
            return items.filter { $0.isUtensil && matchesName($0.category, category.name) }.count
        }
    }

    private static func deleteRecipes(in categoryName: String, context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Recipe>()
        let recipes = ((try? context.fetch(descriptor)) ?? []).filter { recipe in
            recipe.categories.contains(where: { matchesName($0, categoryName) })
        }

        for recipe in recipes {
            context.delete(recipe)
        }

        return recipes.count
    }

    private static func reassignCategoryReferences(from oldName: String, to newName: String, type: CategoryType, context: ModelContext) {
        switch type.canonicalType {
        case .pantry, .grocery:
            let descriptor = FetchDescriptor<UnifiedItem>()
            for item in ((try? context.fetch(descriptor)) ?? []) where (item.isPantry || item.isGrocery) && matchesName(item.category, oldName) {
                item.category = newName
            }

        case .recipe:
            let descriptor = FetchDescriptor<Recipe>()
            for recipe in ((try? context.fetch(descriptor)) ?? []) where recipe.categories.contains(where: { matchesName($0, oldName) }) {
                var uniqueKeys = Set<String>()
                let updatedCategories = recipe.categories.compactMap { categoryName -> String? in
                    let candidate = matchesName(categoryName, oldName) ? newName : categoryName
                    let key = normalizedKey(for: candidate)
                    guard uniqueKeys.insert(key).inserted else { return nil }
                    return candidate
                }
                recipe.categories = updatedCategories.isEmpty ? [defaultRecipeCategoryName(context: context)] : updatedCategories
            }

        case .utensil:
            let descriptor = FetchDescriptor<UnifiedItem>()
            for item in ((try? context.fetch(descriptor)) ?? []) where item.isUtensil && matchesName(item.category, oldName) {
                item.category = newName
            }
        }
    }
}
