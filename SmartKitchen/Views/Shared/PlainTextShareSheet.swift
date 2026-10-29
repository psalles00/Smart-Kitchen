import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PlainTextSharePayload: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

/// Builds a snapshot only when the user asks to share. No media, database writes or network requests.
@MainActor
enum SavoriaPlainTextExport {
    static var attribution: String { String(localized: "Compartilhado com Savoria") }

    static func list(title: String, items: [UnifiedItem]) -> String {
        let rows = items.map { item in
            var parts = [item.name]
            if let quantity = item.quantity {
                let amount = quantity.formatted(.number.precision(.fractionLength(0...2)))
                let unit = item.unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                parts.append(unit.isEmpty ? amount : "\(amount) \(unit)")
            }
            let note = item.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { parts.append(note) }
            return "• " + parts.joined(separator: " — ")
        }
        return ([title] + rows + ["", attribution]).joined(separator: "\n")
    }

    static func recipe(_ recipe: Recipe, servings: Int? = nil) -> String {
        let servingCount = max(servings ?? recipe.servings, 1)
        let multiplier = Double(servingCount) / Double(max(recipe.servings, 1))
        var blocks = [recipe.name]
        if !recipe.descriptionText.isEmpty { blocks.append(recipe.descriptionText) }
        blocks.append("\(String(localized: "Porções")): \(servingCount)")
        if recipe.totalTime > 0 { blocks.append("\(String(localized: "Tempo total")): \(recipe.totalTime) min") }
        let ingredients = (recipe.ingredients ?? []).sorted { $0.sortOrder < $1.sortOrder }
        let sections = (recipe.ingredientSections ?? []).sorted { $0.sortOrder < $1.sortOrder }
        if !ingredients.isEmpty {
            var lines = [String(localized: "Ingredientes")]
            func appendIngredient(_ ingredient: RecipeIngredient) {
                var amountParts: [String] = []
                if let quantity = ingredient.quantity {
                    amountParts.append((quantity * multiplier).formatted(.number.precision(.fractionLength(0...2))))
                    let unit = RecipeOptionCatalog.ingredientLabel(for: ingredient.unit, kind: .unit)
                    if !unit.isEmpty { amountParts.append(unit) }
                }
                if !ingredient.formattedState.isEmpty { amountParts.append(ingredient.formattedState) }
                let amount = amountParts.joined(separator: " ")
                lines.append("• " + ingredient.name + (amount.isEmpty ? "" : " — " + amount))
            }
            let sectionIDs = Set(sections.map(\.id))
            for ingredient in ingredients where ingredient.sectionID == nil || !sectionIDs.contains(ingredient.sectionID!) {
                appendIngredient(ingredient)
            }
            for section in sections {
                let group = ingredients.filter { $0.sectionID == section.id }
                guard !group.isEmpty else { continue }
                lines.append(section.title)
                if !section.subtitle.isEmpty { lines.append(section.subtitle) }
                for ingredient in group { appendIngredient(ingredient) }
            }
            blocks.append(lines.joined(separator: "\n"))
        }
        let steps = (recipe.steps ?? []).sorted { $0.order < $1.order }
        if !steps.isEmpty {
            blocks.append(([String(localized: "Modo de preparo")] + steps.enumerated().map {
                "\($0.offset + 1). \($0.element.instruction)"
            }).joined(separator: "\n"))
        }
        let source = recipe.externalURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: source), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            blocks.append("\(String(localized: "Fonte")): \(source)")
        }
        blocks.append(attribution)
        return blocks.joined(separator: "\n\n")
    }
}

struct PlainTextShareSheet: View {
    let payload: PlainTextSharePayload
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(verbatim: payload.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    ShareLink(item: payload.text, subject: Text(verbatim: payload.title)) {
                        Label("Compartilhar texto", systemImage: "square.and.arrow.up")
                            .frame(minHeight: 44)
                    }
                    Spacer()
                    Button {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(payload.text, forType: .string)
                        #else
                        UIPasteboard.general.string = payload.text
                        #endif
                        copied = true
                    } label: {
                        Label(copied ? String(localized: "Texto copiado") : String(localized: "Copiar texto"),
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(minHeight: 44)
                    }
                }
                .buttonStyle(.bordered)
                .padding()
                .background(.regularMaterial)
            }
            .navigationTitle(payload.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }
}
