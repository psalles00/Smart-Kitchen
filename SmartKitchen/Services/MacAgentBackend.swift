#if os(macOS)
import Foundation
import SwiftData
import CryptoKit
import AppKit
import Darwin
import ImageIO

/// Local JSON RPC over a private Unix socket. All model work stays on MainActor,
/// in the app's existing container; clients never open or write its SQLite stores.
@MainActor
final class MacAgentBackend {
    static let shared = MacAgentBackend()
    private var listener: Int32 = -1
    private var worker: Task<Void, Never>?
    private let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SmartKitchen/Agent", isDirectory: true)
    private var socketURL: URL { root.appendingPathComponent("backend.sock") }

    func start() {
        guard listener < 0 else { return }
        do {
            try privateDirectory(root)
            for name in ["plans", "receipts", "backups"] {
                try privateDirectory(root.appendingPathComponent(name, isDirectory: true))
            }
            listener = try AgentSocket.open(path: socketURL.path)
            let fd = listener
            worker = Task.detached(priority: .utility) {
                await AgentSocket.serve(fd: fd) { data in
                    await MacAgentBackend.shared.handle(data)
                }
            }
            try write(AgentDiscovery(protocolVersion: 1, pid: Int(getpid()), socket: socketURL.path),
                      to: root.appendingPathComponent("backend.json"))
        } catch {
            NSLog("[AgentBackend] Start failed: %@", error.localizedDescription)
        }
    }

    private func handle(_ data: Data) -> Data {
        do {
            let request = try JSONDecoder().decode(AgentRequest.self, from: data)
            guard let id = UUID(uuidString: request.requestID) else { throw AgentError.invalid("requestID must be a UUID") }
            let container = CloudSyncService.shared.container
            let expectedURLs = Set([CloudSyncService.privateStoreURL.standardizedFileURL,
                                    CloudSyncService.sharedStoreURL.standardizedFileURL])
            let actualURLs = Set(CloudSyncService.shared.container.configurations.map { $0.url.standardizedFileURL })
            guard expectedURLs.isSubset(of: actualURLs) else {
                throw AgentError.invalid("Persistent stores unavailable; temporary containers cannot be edited")
            }
            // Do not overwrite a pending edit from the app's UI.
            guard !container.mainContext.hasChanges else { throw AgentError.conflict("App has unsaved edits; retry after autosave") }
            // A fresh request context sees current CloudKit data and isolates failed edits from the UI.
            let context = ModelContext(container)
            context.autosaveEnabled = false
            switch request.method {
            case "health":
                return try encode(AgentReply(ok: true, result: .health(pid: Int(getpid()), visibleWindows: NSApplication.shared.windows.filter(\.isVisible).count)))
            case "backup":
                let url = root.appendingPathComponent("backups/\(id.uuidString).zip")
                let archive = try BackupSnapshotV2.makeArchive(context: context, includeMedia: true)
                try privateWrite(archive, to: url)
                return try encode(AgentReply(ok: true, result: .backup(url.path)))
            case "snapshot":
                return try encode(AgentReply(ok: true, result: .snapshot(try snapshot(context))))
            case "self-test":
                return try encode(AgentReply(ok: true, result: .tests(try validateSandbox())))
            case "plan":
                guard let manifest = request.manifest else { throw AgentError.invalid("manifest is required") }
                try validate(manifest)
                let before = try snapshot(context)
                guard request.expectedRevision == before.revision else { throw AgentError.conflict("Revision changed") }
                let plan = AgentPlan(id: id, beforeRevision: before.revision, manifest: manifest,
                                     summary: summary(manifest, before: before))
                if FileManager.default.fileExists(atPath: planURL(id).path) {
                    let previous = try Data(contentsOf: planURL(id))
                    guard previous == (try encode(plan)) else { throw AgentError.conflict("Plan requestID already used for different content") }
                }
                try write(plan, to: planURL(id))
                return try encode(AgentReply(ok: true, result: .plan(plan)))
            case "apply":
                guard let planID = request.planID else { throw AgentError.invalid("planID is required") }
                let receiptURL = root.appendingPathComponent("receipts/\(id.uuidString).json")
                if FileManager.default.fileExists(atPath: receiptURL.path) {
                    let receipt = try JSONDecoder().decode(AgentReceipt.self, from: Data(contentsOf: receiptURL))
                    guard receipt.planID == planID else { throw AgentError.conflict("requestID already used for another plan") }
                    return try encode(AgentReply(ok: true, result: .receipt(receipt, replayed: true)))
                }
                let plan = try JSONDecoder().decode(AgentPlan.self, from: Data(contentsOf: planURL(planID)))
                try validate(plan.manifest)
                let before = try snapshot(context)
                let intentURL = root.appendingPathComponent("receipts/\(id.uuidString).intent.json")
                let backup = root.appendingPathComponent("backups/\(id.uuidString).zip")
                if FileManager.default.fileExists(atPath: intentURL.path) {
                    let intent = try JSONDecoder().decode(AgentPlan.self, from: Data(contentsOf: intentURL))
                    guard intent.id == plan.id, (try encode(intent)) == (try encode(plan)) else {
                        throw AgentError.conflict("requestID already used for another intent")
                    }
                    if matches(plan.manifest, snapshot: before), FileManager.default.fileExists(atPath: backup.path) {
                        let receipt = AgentReceipt(requestID: id, planID: plan.id, beforeRevision: plan.beforeRevision,
                                                   afterRevision: before.revision, backup: backup.path,
                                                   counts: before.counts, appliedAt: Date())
                        try write(receipt, to: receiptURL)
                        return try encode(AgentReply(ok: true, result: .receipt(receipt, replayed: true)))
                    }
                }
                guard request.expectedRevision == plan.beforeRevision, before.revision == plan.beforeRevision else {
                    throw AgentError.conflict("Revision changed; make a fresh plan before applying")
                }
                // Complete export precedes any edit. Media is included even when cloud media sync is disabled.
                if !FileManager.default.fileExists(atPath: backup.path) {
                    let archive = try BackupSnapshotV2.makeArchive(context: context, includeMedia: true)
                    try privateWrite(archive, to: backup)
                }
                // Intent journal makes an interrupted save auditable. Replay is also safe by stable item IDs.
                try write(plan, to: root.appendingPathComponent("receipts/\(id.uuidString).intent.json"))
                do {
                    try mutate(plan.manifest, context: context)
                    try context.save()
                } catch {
                    // Roll back only this unsaved context transaction, never restore old stores or files.
                    context.rollback()
                    throw error
                }
                let after = try snapshot(context)
                guard matches(plan.manifest, snapshot: after) else {
                    throw AgentError.conflict("Save needs reconciliation; inspect snapshot and intent, do not blindly retry")
                }
                let receipt = AgentReceipt(requestID: id, planID: plan.id, beforeRevision: before.revision,
                                           afterRevision: after.revision, backup: backup.path,
                                           counts: after.counts, appliedAt: Date())
                try write(receipt, to: receiptURL)
                NotificationCenter.default.post(name: .homeDataShouldRefresh, object: nil)
                return try encode(AgentReply(ok: true, result: .receipt(receipt, replayed: false)))
            case "shutdown":
                // Lifecycle API for a clean update, not UI automation. Allow response to flush first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApplication.shared.terminate(nil) }
                return try encode(AgentReply(ok: true, result: .health(pid: Int(getpid()), visibleWindows: NSApplication.shared.windows.filter(\.isVisible).count)))
            default: throw AgentError.invalid("Unknown method")
            }
        } catch {
            return (try? encode(AgentReply(ok: false, error: error.localizedDescription,
                                          status: (error as? AgentError)?.status ?? (error is DecodingError ? 400 : 500)))) ?? Data("{\"ok\":false,\"status\":500}".utf8)
        }
    }

    private func snapshot(_ context: ModelContext) throws -> AgentSnapshot {
        let items = try context.fetch(FetchDescriptor<UnifiedItem>()).map(AgentItem.init).sorted { $0.id.uuidString < $1.id.uuidString }
        let categories = try context.fetch(FetchDescriptor<Category>()).map(AgentCategory.init).sorted { $0.id.uuidString < $1.id.uuidString }
        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first
        let grouping = ["pantry": settings?.pantryGroupingMode.rawValue ?? "category",
                        "grocery": settings?.groceryGroupingMode.rawValue ?? "marketSection"]
        let recipes = try context.fetch(FetchDescriptor<Recipe>()).map(AgentRecipe.init).sorted { $0.id.uuidString < $1.id.uuidString }
        let state = AgentState(items: items, categories: categories, recipes: recipes, showReserve: settings?.showReserve ?? false, grouping: grouping)
        let digest = SHA256.hash(data: try encode(state)).map { String(format: "%02x", $0) }.joined()
        return AgentSnapshot(revision: digest, items: items, categories: categories,
                             showReserve: state.showReserve, counts: counts(items).merging(["recipes": recipes.count]) { _, new in new }, grouping: grouping, recipes: recipes)
    }

    /// Uses an isolated in-memory model container; never edits production data or syncs fixtures.
    private func validateSandbox() throws -> [String] {
        let config = ModelConfiguration(schema: CloudSyncService.appSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: CloudSyncService.appSchema, configurations: config)
        let context = ModelContext(container); context.autosaveEnabled = false
        let item = UnifiedItem(name: "API Fixture", imageData: Data([1, 2, 3]), isPantry: true, isUtensil: true,
                               expirationDate: Date(timeIntervalSince1970: 1900000000))
        let extra = UnifiedItem(name: "Archived Fixture", isGrocery: true)
        context.insert(item); context.insert(extra); try context.save()
        let entry = AgentEntry(id: item.id, name: "API Fixture Updated", notes: "Literal notes", category: "Fixture Category",
                               quantity: 2, unit: "un", iconName: nil, isChecked: false, lists: ["reserve"], orders: ["reserve": 0],
                               thingsID: nil, thingsTags: nil, thingsChecklist: nil)
        let manifest = AgentManifest(mode: "replaceLists", source: "isolated self-test", items: [entry], categories: ["Fixture Category"], showReserve: false)
        try validate(manifest); try mutate(manifest, context: context); try context.save()
        let first = try snapshot(context)
        guard matches(manifest, snapshot: first), first.items.count == 2, item.isUtensil,
              item.imageData == Data([1, 2, 3]), item.expirationDate == Date(timeIntervalSince1970: 1900000000),
              extra.activeFlags.isEmpty else { throw AgentError.invalid("Sandbox preservation test failed") }
        try mutate(manifest, context: context); try context.save()
        guard try snapshot(context).revision == first.revision else { throw AgentError.invalid("Sandbox idempotency test failed") }
        let invalid = AgentManifest(mode: "replaceLists", source: "isolated self-test", items: [entry, entry], categories: [], showReserve: false)
        do { try validate(invalid); throw AgentError.invalid("Sandbox duplicate ID was accepted") }
        catch AgentError.invalid(let message) where message == "Invalid or duplicate item identity/fields" {}
        let duplicate = UnifiedItem(name: "Independent Duplicate", isPantry: true)
        duplicate.id = UUID(uuidString: "5a760a1a-0000-8000-8000-000000000001")!
        context.insert(duplicate); context.insert(UnifiedItem(name: "Independent Duplicate", isPantry: true)); try context.save()
        guard try UnifiedItem.mergeDuplicateNames(in: context) == 0 else { throw AgentError.invalid("Sandbox independent identities were merged") }
        context.insert(UnifiedItem(name: "Legacy Duplicate")); context.insert(UnifiedItem(name: "Legacy Duplicate")); try context.save()
        guard try UnifiedItem.mergeDuplicateNames(in: context) == 1 else { throw AgentError.invalid("Sandbox legacy deduplication regressed") }
        let recipe = Recipe(name: "Existing recipe", imageData: Data([4, 5, 6]), isFavorite: true)
        recipe.proteinG = 12; context.insert(recipe); try context.save()
        var recipeEntry = AgentRecipe(id: recipe.id, name: "Edited recipe")
        recipeEntry.descriptionText = "Verbatim vault data"
        var recipeManifest = AgentManifest(mode: "upsert", source: "isolated recipe test", items: [], categories: [], showReserve: false)
        recipeManifest.recipes = [recipeEntry]
        try validate(recipeManifest); try mutate(recipeManifest, context: context); try context.save()
        guard recipe.isFavorite, recipe.proteinG == 12, recipe.imageData == Data([4, 5, 6]),
              matches(recipeManifest, snapshot: try snapshot(context)) else { throw AgentError.invalid("Recipe preservation test failed") }
        let revision = try snapshot(context).revision
        try mutate(recipeManifest, context: context); try context.save()
        guard try snapshot(context).revision == revision else { throw AgentError.invalid("Recipe idempotence test failed") }
        let structured = """
        {"mode":"upsert","source":"fixture","items":[],"categories":[],"showReserve":false,"recipes":[{
        "id":"00000000-0000-4000-8000-000000000001","name":"Structured fixture",
        "sections":[{"id":"00000000-0000-4000-8000-000000000002","title":"Main","subtitle":"","sortOrder":0}],
        "ingredients":[{"id":"00000000-0000-4000-8000-000000000003","name":"Rice","quantity":100,"unit":"g","preparationState":"","sortOrder":0,"sectionID":"00000000-0000-4000-8000-000000000002"}],
        "steps":[{"id":"00000000-0000-4000-8000-000000000004","order":1,"instruction":"Cook rice"}]}]}
        """
        let structuredManifest = try JSONDecoder().decode(AgentManifest.self, from: Data(structured.utf8))
        try validate(structuredManifest); try mutate(structuredManifest, context: context); try context.save()
        guard matches(structuredManifest, snapshot: try snapshot(context)),
              try context.fetch(FetchDescriptor<RecipeIngredient>()).count == 1,
              try context.fetch(FetchDescriptor<RecipeStep>()).count == 1 else { throw AgentError.invalid("Recipe relationships failed") }
        let structuredRevision = try snapshot(context).revision
        try mutate(structuredManifest, context: context); try context.save()
        guard try snapshot(context).revision == structuredRevision else { throw AgentError.invalid("Structured recipe replay failed") }
        return ["memberships and order", "retained records and IDs", "retained photos/expiry/utensils", "idempotent upsert", "duplicate-ID rejection", "independent and legacy identity handling", "recipe metadata preservation", "recipe idempotence", "structured recipe relationships", "structured replay"]
    }

    private func validate(_ manifest: AgentManifest) throws {
        guard ["replaceLists", "upsert"].contains(manifest.mode),
              (!manifest.items.isEmpty || (manifest.mode == "upsert" && !(manifest.recipes ?? []).isEmpty)), manifest.items.count <= 2000,
              manifest.categories.count <= 100 else { throw AgentError.invalid("Invalid mode or manifest size") }
        try validateRecipes(manifest.recipes ?? [])
        var ids = Set<UUID>()
        for item in manifest.items {
            guard ids.insert(item.id).inserted, !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.name.count <= 300, item.notes.count <= 20000, item.category.count <= 120,
                  Set(item.lists).isSubset(of: Set(["pantry", "reserve", "grocery"])),
                  Set(item.lists).count == item.lists.count,
                  Set(item.orders.keys).isSubset(of: Set(item.lists)),
                  item.quantity.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  item.orders.values.allSatisfy({ $0 >= 0 && $0 <= 100000 }) else {
                throw AgentError.invalid("Invalid or duplicate item identity/fields")
            }
        }
        guard Set(manifest.categories).count == manifest.categories.count,
              manifest.categories.allSatisfy({ !$0.isEmpty && $0.count <= 120 }) else {
            throw AgentError.invalid("Invalid categories")
        }
        if let grouping = manifest.grouping {
            guard Set(grouping.keys).isSubset(of: ["pantry", "grocery"]),
                  grouping.values.allSatisfy({ ListGroupingMode(rawValue: $0) != nil }) else {
                throw AgentError.invalid("Invalid grouping modes")
            }
        }
    }

    private func mutate(_ manifest: AgentManifest, context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<UnifiedItem>())
        let grouped = Dictionary(grouping: existing, by: \.id)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else { throw AgentError.conflict("Duplicate database IDs; resolve before editing") }
        let byID = grouped.mapValues { $0[0] }
        let desiredIDs = Set(manifest.items.map(\.id))
        if manifest.mode == "replaceLists" {
            // Archive membership only. Existing records, links, photos and metadata remain available via snapshot.
            for item in existing where !desiredIDs.contains(item.id) {
                item.isPantry = false; item.isReserve = false; item.isGrocery = false
            }
        }
        for entry in manifest.items {
            let item = byID[entry.id] ?? UnifiedItem(name: entry.name)
            if byID[entry.id] == nil { item.id = entry.id; context.insert(item) }
            item.name = entry.name; item.descriptionText = entry.notes; item.category = entry.category
            item.quantity = entry.quantity; item.unit = entry.unit
            if let icon = entry.iconName { item.iconName = icon }
            item.isPantry = entry.lists.contains("pantry")
            item.isReserve = entry.lists.contains("reserve")
            item.isGrocery = entry.lists.contains("grocery")
            if let order = entry.orders["pantry"] { item.pantrySortOrder = order }
            if let order = entry.orders["reserve"] { item.reserveSortOrder = order }
            if let order = entry.orders["grocery"] { item.grocerySortOrder = order }
            if let checked = entry.isChecked { item.isChecked = checked }
            // Expiry, images, fixed/linked flags, utensil membership and relationships are intentionally retained.
        }
        try mutateRecipes(manifest.recipes ?? [], context: context)
        for (index, name) in manifest.categories.enumerated() {
            let category = CategoryMutationService.ensureCategory(named: name, type: .pantry, context: context)
            category.sortOrder = index
        }
        if let settings = try context.fetch(FetchDescriptor<AppSettings>()).first {
            if manifest.showReserve { settings.showReserve = true }
            if let mode = manifest.grouping?["pantry"] { settings.pantryGroupingModeRaw = mode }
            if let mode = manifest.grouping?["grocery"] { settings.groceryGroupingModeRaw = mode }
        }
    }

    private func matches(_ manifest: AgentManifest, snapshot: AgentSnapshot) -> Bool {
        guard matchesRecipes(manifest.recipes ?? [], actual: snapshot.recipes) else { return false }
        let byID = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
        for entry in manifest.items {
            guard let item = byID[entry.id], item.name == entry.name, item.notes == entry.notes,
                  item.category == entry.category, item.quantity == entry.quantity, item.unit == entry.unit,
                  Set(item.lists.filter { $0 != "utensil" }) == Set(entry.lists),
                  entry.isChecked.map({ $0 == item.isChecked }) ?? true,
                  entry.iconName.map({ $0 == item.iconName }) ?? true,
                  entry.orders.allSatisfy({ item.orders[$0.key] == $0.value }) else { return false }
        }
        if manifest.mode == "replaceLists" {
            let ids = Set(manifest.items.map(\.id))
            guard snapshot.items.allSatisfy({ ids.contains($0.id) || Set($0.lists).isDisjoint(with: ["pantry", "reserve", "grocery"]) }) else { return false }
        }
        if manifest.showReserve && !snapshot.showReserve { return false }
        if let grouping = manifest.grouping,
           !grouping.allSatisfy({ snapshot.grouping[$0.key] == $0.value }) { return false }
        for (index, name) in manifest.categories.enumerated() {
            guard snapshot.categories.contains(where: { $0.type == "pantry" && $0.name == name && $0.order == index }) else { return false }
        }
        return true
    }

    private func coverData(_ entry: AgentRecipe) throws -> Data? {
        guard let path = entry.coverPath else { return nil }
        guard path.hasPrefix("/"), let expected = entry.coverSHA256,
              (try URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 20 * 1024 * 1024 else {
            throw AgentError.invalid("Cover requires absolute path, SHA256 and size <=20MiB")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard AgentRecipe.digest(data) == expected,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            throw AgentError.conflict("Cover changed or is not an image; create a fresh plan")
        }
        return data
    }

    private func validateRecipes(_ entries: [AgentRecipe]) throws {
        guard entries.count <= 500 else { throw AgentError.invalid("Too many recipes") }
        var ids = Set<UUID>(), childIDs = Set<UUID>()
        for entry in entries {
            guard ids.insert(entry.id).inserted, !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  entry.name.count <= 300, (entry.descriptionText?.count ?? 0) <= 200000,
                  entry.servings.map({ $0 > 0 && $0 <= 10000 }) ?? true,
                  entry.prepTime.map({ $0 >= 0 }) ?? true, entry.cookTime.map({ $0 >= 0 }) ?? true,
                  entry.difficulty.map({ Difficulty(rawValue: $0) != nil }) ?? true,
                  entry.imageSHA256 == nil, entry.createdAt == nil, entry.updatedAt == nil,
                  entry.media == nil, entry.nutrition == nil,
                  entry.coverPath != nil || entry.coverSHA256 == nil else {
                throw AgentError.invalid("Invalid recipe fields or read-only metadata supplied")
            }
            for ingredients in [entry.ingredients ?? []] {
                guard ingredients.count <= 1000, Set(ingredients.map(\.id)).count == ingredients.count,
                      ingredients.allSatisfy({ !$0.name.isEmpty && $0.sortOrder >= 0 && ($0.quantity.map { $0.isFinite && $0 >= 0 } ?? true) }) else {
                    throw AgentError.invalid("Invalid ingredients")
                }
            }
            let steps = entry.steps ?? [], sections = entry.sections ?? []
            guard steps.count <= 1000, Set(steps.map(\.id)).count == steps.count,
                  steps.allSatisfy({ !$0.instruction.isEmpty && $0.order >= 0 && ($0.durationMinutes.map { $0 >= 0 } ?? true) }),
                  sections.count <= 100, Set(sections.map(\.id)).count == sections.count else {
                throw AgentError.invalid("Invalid recipe steps or sections")
            }
            for childID in (entry.ingredients ?? []).map(\.id) + sections.map(\.id) + steps.map(\.id) {
                guard childIDs.insert(childID).inserted else { throw AgentError.invalid("Duplicate child identity in manifest") }
            }
            _ = try coverData(entry)
        }
    }

    private func mutateRecipes(_ entries: [AgentRecipe], context: ModelContext) throws {
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        let grouped = Dictionary(grouping: recipes, by: \.id)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else { throw AgentError.conflict("Duplicate recipe IDs") }
        let byID = grouped.mapValues { $0[0] }
        // Child IDs belong to one recipe. Never reparent another recipe's data.
        let ingredientOwners = try context.fetch(FetchDescriptor<RecipeIngredient>())
        let sectionOwners = try context.fetch(FetchDescriptor<RecipeIngredientSection>())
        let stepOwners = try context.fetch(FetchDescriptor<RecipeStep>())
        for entry in entries {
            if let existing = byID[entry.id], matchesRecipes([entry], actual: [AgentRecipe(existing)]) { continue }
            let sectionIDs = Set((byID[entry.id]?.ingredientSections ?? []).map(\.id) + (entry.sections ?? []).map(\.id))
            guard (entry.ingredients ?? []).allSatisfy({ $0.sectionID.map { sectionIDs.contains($0) } ?? true }) else {
                throw AgentError.invalid("Ingredient section is not part of this recipe")
            }
            for child in entry.ingredients ?? [] where ingredientOwners.contains(where: { $0.id == child.id && $0.recipe?.id != entry.id }) {
                throw AgentError.conflict("Ingredient identity belongs to another recipe")
            }
            for child in entry.sections ?? [] where sectionOwners.contains(where: { $0.id == child.id && $0.recipe?.id != entry.id }) {
                throw AgentError.conflict("Section identity belongs to another recipe")
            }
            for child in entry.steps ?? [] where stepOwners.contains(where: { $0.id == child.id && $0.recipe?.id != entry.id }) {
                throw AgentError.conflict("Step identity belongs to another recipe")
            }
            let recipe = byID[entry.id] ?? Recipe(name: entry.name)
            if byID[entry.id] == nil { recipe.id = entry.id; context.insert(recipe) }
            recipe.name = entry.name
            if let value = entry.descriptionText { recipe.descriptionText = value }
            if let value = entry.externalURLString { recipe.externalURLString = value }
            if let value = entry.category { recipe.category = value }
            if let value = entry.tags { recipe.tags = value }
            if let value = entry.prepTime { recipe.prepTime = value }
            if let value = entry.cookTime { recipe.cookTime = value }
            if let value = entry.servings { recipe.servings = value }
            if let value = entry.difficulty, let difficulty = Difficulty(rawValue: value) { recipe.difficulty = difficulty }
            if let value = entry.isFavorite { recipe.isFavorite = value }
            if let value = entry.requiredUtensils { recipe.requiredUtensils = value }
            if let data = try coverData(entry) { recipe.imageData = data }
            for entry in entry.sections ?? [] {
                let section = (recipe.ingredientSections ?? []).first { $0.id == entry.id } ?? RecipeIngredientSection()
                if section.recipe == nil { section.id = entry.id; context.insert(section); section.recipe = recipe; if !(recipe.ingredientSections ?? []).contains(where: { $0.id == section.id }) { recipe.ingredientSections = (recipe.ingredientSections ?? []) + [section] } }
                section.title = entry.title; section.subtitle = entry.subtitle; section.sortOrder = entry.sortOrder
            }
            for entry in entry.ingredients ?? [] {
                let ingredient = (recipe.ingredients ?? []).first { $0.id == entry.id } ?? RecipeIngredient(name: entry.name)
                if ingredient.recipe == nil { ingredient.id = entry.id; context.insert(ingredient); ingredient.recipe = recipe; if !(recipe.ingredients ?? []).contains(where: { $0.id == ingredient.id }) { recipe.ingredients = (recipe.ingredients ?? []) + [ingredient] } }
                ingredient.name = entry.name; ingredient.quantity = entry.quantity; ingredient.unit = entry.unit
                if let icon = entry.iconName { ingredient.iconName = icon }
                ingredient.preparationState = entry.preparationState; ingredient.sortOrder = entry.sortOrder; ingredient.sectionID = entry.sectionID
            }
            for entry in entry.steps ?? [] {
                let step = (recipe.steps ?? []).first { $0.id == entry.id } ?? RecipeStep(order: entry.order, instruction: entry.instruction)
                if step.recipe == nil { step.id = entry.id; context.insert(step); step.recipe = recipe; if !(recipe.steps ?? []).contains(where: { $0.id == step.id }) { recipe.steps = (recipe.steps ?? []) + [step] } }
                step.order = entry.order; step.instruction = entry.instruction; step.durationMinutes = entry.durationMinutes
            }
            recipe.updatedAt = .now
        }
    }

    private func matchesRecipes(_ desired: [AgentRecipe], actual: [AgentRecipe]) -> Bool {
        let byID = Dictionary(grouping: actual, by: \.id)
        for entry in desired {
            guard let recipe = byID[entry.id]?.first, byID[entry.id]?.count == 1 else { return false }
            guard entry.name == recipe.name,
                  entry.descriptionText.map({ $0 == recipe.descriptionText }) ?? true,
                  entry.externalURLString.map({ $0 == recipe.externalURLString }) ?? true,
                  entry.category.map({ $0 == recipe.category }) ?? true,
                  entry.tags.map({ $0 == recipe.tags }) ?? true,
                  entry.prepTime.map({ $0 == recipe.prepTime }) ?? true,
                  entry.cookTime.map({ $0 == recipe.cookTime }) ?? true,
                  entry.servings.map({ $0 == recipe.servings }) ?? true,
                  entry.difficulty.map({ $0 == recipe.difficulty }) ?? true,
                  entry.isFavorite.map({ $0 == recipe.isFavorite }) ?? true,
                  entry.requiredUtensils.map({ $0 == recipe.requiredUtensils }) ?? true,
                  entry.coverSHA256.map({ $0 == recipe.imageSHA256 }) ?? true,
                  (entry.ingredients ?? []).allSatisfy({ wanted in
                      recipe.ingredients?.contains(where: { got in got.id == wanted.id && got.name == wanted.name && got.quantity == wanted.quantity && got.unit == wanted.unit && got.preparationState == wanted.preparationState && got.sortOrder == wanted.sortOrder && got.sectionID == wanted.sectionID && (wanted.iconName.map { $0 == got.iconName } ?? true) }) == true
                  }),
                  (entry.sections ?? []).allSatisfy({ recipe.sections?.contains($0) == true }),
                  (entry.steps ?? []).allSatisfy({ recipe.steps?.contains($0) == true }) else { return false }
        }
        return true
    }

    private func counts(_ items: [AgentItem]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: ["pantry", "reserve", "grocery", "utensil"].map { list in
            (list, items.filter { $0.lists.contains(list) }.count)
        })
    }
    private func summary(_ manifest: AgentManifest, before: AgentSnapshot) -> AgentSummary {
        let current = Set(before.items.map(\.id)), desired = Set(manifest.items.map(\.id))
        let previousRecipeIDs = Set(before.recipes.map(\.id)), recipeIDs = Set((manifest.recipes ?? []).map(\.id))
        return AgentSummary(recipesCreated: recipeIDs.subtracting(previousRecipeIDs).count, recipesUpdated: recipeIDs.intersection(previousRecipeIDs).count, created: desired.subtracting(current).count,
                            updated: desired.intersection(current).count,
                            archived: manifest.mode == "replaceLists" ? before.items.filter {
                                !desired.contains($0.id) && !Set($0.lists).isDisjoint(with: ["pantry", "reserve", "grocery"])
                            }.count : 0,
                            desiredCounts: Dictionary(uniqueKeysWithValues: ["pantry", "reserve", "grocery"].map { list in
                                (list, manifest.items.filter { $0.lists.contains(list) }.count)
                            }))
    }
    private func planURL(_ id: UUID) -> URL { root.appendingPathComponent("plans/\(id.uuidString).json") }
    private func privateDirectory(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attrs[.type] as? FileAttributeType == .typeDirectory,
                  (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid() else {
                throw AgentError.invalid("Private backend directory must be owned by current user, without symlinks")
            }
        } else { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    private func privateWrite(_ data: Data, to url: URL) throws {
        if url.pathExtension == "zip" {
            let available = try root.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0
            guard Int64(available) - Int64(data.count) > 10 * 1024 * 1024 * 1024 else { throw AgentError.invalid("Backup would leave less than 10GiB free") }
        }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func write<T: Encodable>(_ value: T, to url: URL) throws { try privateWrite(encode(value), to: url) }
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }
}

private enum AgentError: LocalizedError {
    case invalid(String), conflict(String)
    var errorDescription: String? { switch self { case .invalid(let message), .conflict(let message): message } }
    var status: Int { switch self { case .invalid: 400; case .conflict: 409 } }
}
private struct AgentDiscovery: Codable { let protocolVersion: Int; let pid: Int; let socket: String }
private struct AgentRequest: Decodable {
    let requestID: String; let method: String; let expectedRevision: String?
    let manifest: AgentManifest?; let planID: UUID?
}
private struct AgentManifest: Codable {
    let mode: String; let source: String; let items: [AgentEntry]; let categories: [String]; let showReserve: Bool
    var grouping: [String: String]? = nil
    var recipes: [AgentRecipe]? = nil
}
private struct AgentEntry: Codable {
    let id: UUID; let name: String; let notes: String; let category: String
    let quantity: Double?; let unit: String?; let iconName: String?; let isChecked: Bool?
    let lists: [String]; let orders: [String: Int]
    let thingsID: String?; let thingsTags: [String]?; let thingsChecklist: [AgentChecklist]?
}
private struct AgentChecklist: Codable { let title: String; let status: String?; let uuid: String? }
private struct AgentItem: Codable {
    let id: UUID; let name: String; let notes: String; let category: String
    let quantity: Double?; let unit: String?; let iconName: String?; let imageSHA256: String?
    let expirationDate: Date?; let defaultExpiryDays: Int?; let addedAt: Date
    let isChecked: Bool; let isFixed: Bool; let isLinkedToGrocery: Bool; let linkedPantryItemId: UUID?
    let lists: [String]; let orders: [String: Int]
    init(_ item: UnifiedItem) {
        id = item.id; name = item.name; notes = item.descriptionText; category = item.category
        quantity = item.quantity; unit = item.unit; iconName = item.iconName
        imageSHA256 = item.imageData.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
        expirationDate = item.expirationDate; defaultExpiryDays = item.defaultExpiryDays; addedAt = item.addedAt
        isChecked = item.isChecked; isFixed = item.isFixed; isLinkedToGrocery = item.isLinkedToGrocery; linkedPantryItemId = item.linkedPantryItemId
        lists = item.activeFlags.map(\.rawValue)
        orders = ["pantry": item.pantrySortOrder, "reserve": item.reserveSortOrder, "grocery": item.grocerySortOrder, "utensil": item.utensilSortOrder]
    }
}
private struct AgentCategory: Codable {
    let id: UUID; let name: String; let type: String; let iconName: String?; let order: Int
    init(_ category: Category) { id = category.id; name = category.name; type = category.type.rawValue; iconName = category.iconName; order = category.sortOrder }
}
private struct AgentState: Encodable { let items: [AgentItem]; let categories: [AgentCategory]; let recipes: [AgentRecipe]; let showReserve: Bool; let grouping: [String: String] }
private struct AgentSnapshot: Codable {
    let revision: String; let items: [AgentItem]; let categories: [AgentCategory]; let showReserve: Bool; let counts: [String: Int]; let grouping: [String: String]; let recipes: [AgentRecipe]
}
private struct AgentSummary: Codable { let recipesCreated: Int; let recipesUpdated: Int; let created: Int; let updated: Int; let archived: Int; let desiredCounts: [String: Int] }
private struct AgentPlan: Codable { let id: UUID; let beforeRevision: String; let manifest: AgentManifest; let summary: AgentSummary }
private struct AgentReceipt: Codable {
    let requestID: UUID; let planID: UUID; let beforeRevision: String; let afterRevision: String
    let backup: String; let counts: [String: Int]; let appliedAt: Date
}
private struct AgentReply: Encodable {
    var ok: Bool; var result: AgentResult? = nil; var error: String? = nil; var status: Int = 200
}
private enum AgentResult: Encodable {
    case backup(String), health(pid: Int, visibleWindows: Int), snapshot(AgentSnapshot), plan(AgentPlan), receipt(AgentReceipt, replayed: Bool), tests([String])
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .health(let pid, let visibleWindows):
            try container.encode(pid, forKey: .pid); try container.encode(visibleWindows, forKey: .visibleWindows)
        case .backup(let path): try container.encode(path, forKey: .backup)
        case .tests(let passed): try container.encode(passed, forKey: .passed)
        case .snapshot(let snapshot): try snapshot.encode(to: encoder)
        case .plan(let plan): try plan.encode(to: encoder)
        case .receipt(let receipt, let replayed):
            try container.encode(receipt, forKey: .receipt); try container.encode(replayed, forKey: .replayed)
        }
    }
    private enum Key: CodingKey { case pid, visibleWindows, receipt, replayed, passed, backup }
}

private struct AgentRecipe: Codable {
    var id: UUID; var name: String
    var descriptionText: String? = nil; var externalURLString: String? = nil
    var category: String? = nil; var tags: [String]? = nil
    var prepTime: Int? = nil; var cookTime: Int? = nil; var servings: Int? = nil
    var difficulty: String? = nil; var isFavorite: Bool? = nil; var requiredUtensils: [String]? = nil
    var ingredients: [AgentRecipeIngredient]? = nil; var sections: [AgentRecipeSection]? = nil; var steps: [AgentRecipeStep]? = nil
    var coverPath: String? = nil; var coverSHA256: String? = nil
    // Snapshot-only fields, never accepted as mutation authority.
    var imageSHA256: String? = nil; var media: [AgentRecipeMedia]? = nil
    var nutrition: [String: Double]? = nil; var createdAt: Date? = nil; var updatedAt: Date? = nil
    init(id: UUID, name: String) { self.id = id; self.name = name }
    init(_ recipe: Recipe) {
        id = recipe.id; name = recipe.name; descriptionText = recipe.descriptionText; externalURLString = recipe.externalURLString
        category = recipe.category; tags = recipe.tags; prepTime = recipe.prepTime; cookTime = recipe.cookTime; servings = recipe.servings
        difficulty = recipe.difficulty.rawValue; isFavorite = recipe.isFavorite; requiredUtensils = recipe.requiredUtensils
        imageSHA256 = recipe.imageData.map(Self.digest); createdAt = recipe.createdAt; updatedAt = recipe.updatedAt
        ingredients = (recipe.ingredients ?? []).map(AgentRecipeIngredient.init).sorted { $0.id.uuidString < $1.id.uuidString }
        sections = (recipe.ingredientSections ?? []).map(AgentRecipeSection.init).sorted { $0.id.uuidString < $1.id.uuidString }
        steps = (recipe.steps ?? []).map(AgentRecipeStep.init).sorted { $0.id.uuidString < $1.id.uuidString }
        media = (recipe.preparationMedia ?? []).map(AgentRecipeMedia.init).sorted { $0.id.uuidString < $1.id.uuidString }
        nutrition = [:]
        if let value = recipe.calories { nutrition?["calories"] = Double(value) }
        for (key, value) in [("proteinG", recipe.proteinG), ("carbsG", recipe.carbsG), ("fatG", recipe.fatG), ("fiberG", recipe.fiberG), ("sugarG", recipe.sugarG), ("sodiumMg", recipe.sodiumMg)] {
            if let value { nutrition?[key] = value }
        }
        if let value = recipe.nutritionEstimated { nutrition?["estimated"] = value ? 1 : 0 }
        if let value = recipe.nutritionUpdatedAt { nutrition?["updatedAt"] = value.timeIntervalSinceReferenceDate }
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
private struct AgentRecipeIngredient: Codable, Equatable {
    var id: UUID; var name: String; var quantity: Double?; var unit: String; var preparationState: String
    var sortOrder: Int; var sectionID: UUID?; var iconName: String? = nil
    init(_ value: RecipeIngredient) { id = value.id; name = value.name; quantity = value.quantity; unit = value.unit; preparationState = value.preparationState; sortOrder = value.sortOrder; sectionID = value.sectionID; iconName = value.iconName }
}
private struct AgentRecipeSection: Codable, Equatable {
    var id: UUID; var title: String; var subtitle: String; var sortOrder: Int
    init(_ value: RecipeIngredientSection) { id = value.id; title = value.title; subtitle = value.subtitle; sortOrder = value.sortOrder }
}
private struct AgentRecipeStep: Codable, Equatable {
    var id: UUID; var order: Int; var instruction: String; var durationMinutes: Int?
    init(_ value: RecipeStep) { id = value.id; order = value.order; instruction = value.instruction; durationMinutes = value.durationMinutes }
}
private struct AgentRecipeMedia: Codable {
    var id: UUID; var type: String; var sha256: String; var fileExtension: String; var sortOrder: Int; var sourceOriginal: Bool
    init(_ value: RecipePreparationMedia) { id = value.id; type = value.mediaTypeRaw; sha256 = AgentRecipe.digest(value.data); fileExtension = value.fileExtension; sortOrder = value.sortOrder; sourceOriginal = value.sourceOriginal }
}

private enum AgentSocket {
    nonisolated static func open(path: String) throws -> Int32 {
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [UInt8(0)]
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { throw AgentError.invalid("Socket path too long") }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentError.invalid("Cannot create local socket") }
        var keep = false; defer { if !keep { Darwin.close(fd) } }
        if FileManager.default.fileExists(atPath: path) {
            var info = stat()
            guard lstat(path, &info) == 0, info.st_uid == geteuid(), (info.st_mode & S_IFMT) == S_IFSOCK else {
                throw AgentError.invalid("Refusing to replace a foreign socket or non-socket file")
            }
            let probe = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            let connected = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            } }
            Darwin.close(probe)
            guard connected != 0 else { throw AgentError.conflict("Agent backend already running") }
            guard unlink(path) == 0 else { throw AgentError.invalid("Cannot replace stale socket") }
        }
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        } }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 8) == 0 else { throw AgentError.invalid("Cannot bind private socket") }
        keep = true; return fd
    }
    nonisolated static func serve(fd: Int32, handler: @escaping @Sendable (Data) async -> Data) async {
        while !Task.isCancelled {
            let client = Darwin.accept(fd, nil, nil)
            if client < 0 { if errno == EINTR { continue }; return }
            await serveClient(client, handler: handler)
        }
    }
    nonisolated private static func serveClient(_ fd: Int32, handler: @escaping @Sendable (Data) async -> Data) async {
        defer { Darwin.close(fd) }
        var uid: uid_t = 0; var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == geteuid() else { return }
        var timeout = timeval(tv_sec: 10, tv_usec: 0), noPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout<Int32>.size))
        var input = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while input.count <= 2 * 1024 * 1024 {
            let count = Darwin.recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { return }
            input.append(contentsOf: buffer.prefix(count))
            if let end = input.firstIndex(of: 10) {
                guard end <= 2 * 1024 * 1024 else { return }
                var output = await handler(Data(input.prefix(upTo: end)))
                output.append(10)
                output.withUnsafeBytes { bytes in
                    var sent = 0
                    while sent < output.count {
                        let count = Darwin.send(fd, bytes.baseAddress!.advanced(by: sent), output.count - sent, 0)
                        if count <= 0 { break }; sent += count
                    }
                }
                return
            }
        }
    }
}
#endif
