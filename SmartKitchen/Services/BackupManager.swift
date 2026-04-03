import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class BackupManager {
    static let shared = BackupManager()

    private static let maxBackups = 7
    private static let lastBackupDateKey = "BackupManager.lastBackupDate"

    private(set) var backups: [BackupEntry] = []
    private(set) var isWorking = false

    private let backupsDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        loadBackupList()
    }

    // MARK: - Public

    /// Perform a daily backup if one hasn't been done today.
    func performDailyBackupIfNeeded(context: ModelContext) {
        let calendar = Calendar.current
        if let last = UserDefaults.standard.object(forKey: Self.lastBackupDateKey) as? Date,
           calendar.isDateInToday(last) {
            return
        }
        Task { @MainActor in
            await createBackup(context: context)
        }
    }

    /// Create a full backup now.
    @discardableResult
    func createBackup(context: ModelContext) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }

        do {
            let snapshot = try AppBackupSnapshot(context: context)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let fileName = "backup-\(formatter.string(from: .now)).json"
            let fileURL = backupsDirectory.appendingPathComponent(fileName)

            try data.write(to: fileURL, options: .atomic)

            UserDefaults.standard.set(Date.now, forKey: Self.lastBackupDateKey)

            pruneOldBackups()
            loadBackupList()
            return true
        } catch {
            print("[BackupManager] Failed to create backup: \(error)")
            return false
        }
    }

    /// Restore from a specific backup entry.
    func restore(from entry: BackupEntry, context: ModelContext) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }

        do {
            let data = try Data(contentsOf: entry.url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(AppBackupSnapshot.self, from: data)
            try snapshot.restore(into: context)
            return true
        } catch {
            print("[BackupManager] Failed to restore backup: \(error)")
            return false
        }
    }

    /// Delete a specific backup.
    func delete(_ entry: BackupEntry) {
        try? FileManager.default.removeItem(at: entry.url)
        loadBackupList()
    }

    /// Export a backup entry as zip Data for file exporter.
    func exportData(from entry: BackupEntry) throws -> Data {
        let jsonData = try Data(contentsOf: entry.url)
        return try SimpleZipArchive.archive(fileName: "smart-kitchen-backup.json", data: jsonData)
    }

    /// Export current data as zip Data.
    func exportCurrentData(context: ModelContext) throws -> Data {
        let snapshot = try AppBackupSnapshot(context: context)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        return try SimpleZipArchive.archive(fileName: "smart-kitchen-backup.json", data: data)
    }

    /// Import a zip backup from external file.
    func importBackup(from zipData: Data, context: ModelContext) throws {
        let jsonData = try SimpleZipArchive.extractFile(named: "smart-kitchen-backup.json", from: zipData)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(AppBackupSnapshot.self, from: jsonData)
        try snapshot.restore(into: context)
    }

    /// Reload the list from disk.
    func loadBackupList() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: .skipsHiddenFiles) else {
            backups = []
            return
        }

        backups = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> BackupEntry? in
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                let date = values?.creationDate ?? (try? fm.attributesOfItem(atPath: url.path)[.creationDate] as? Date) ?? .distantPast
                let size = values?.fileSize ?? 0
                return BackupEntry(url: url, date: date, sizeBytes: size)
            }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Private

    private func pruneOldBackups() {
        let fm = FileManager.default
        guard var files = try? fm.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else { return }

        files = files.filter { $0.pathExtension == "json" }
        files.sort { url1, url2 in
            let d1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            let d2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return d1 > d2
        }

        if files.count > Self.maxBackups {
            for url in files[Self.maxBackups...] {
                try? fm.removeItem(at: url)
            }
        }
    }
}

// MARK: - BackupEntry

struct BackupEntry: Identifiable {
    let id = UUID()
    let url: URL
    let date: Date
    let sizeBytes: Int

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }

    var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Hoje"
        } else if calendar.isDateInYesterday(date) {
            return "Ontem"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, d MMM"
            formatter.locale = Locale(identifier: "pt_BR")
            return formatter.string(from: date).localizedCapitalized
        }
    }
}

// MARK: - Shared Backup Snapshot (moved from SettingsView to be reusable)

struct AppBackupSnapshot: Codable {
    let exportedAt: Date
    let appSettings: [AppSettingsRecord]
    let categories: [CategoryRecord]
    let pantryItems: [PantryItemRecord]
    let groceryItems: [GroceryItemRecord]
    let utensilItems: [UtensilItemRecord]
    let recipes: [RecipeRecord]
    let recipeIngredients: [RecipeIngredientRecord]
    let recipeSteps: [RecipeStepRecord]
    let recipePreparationMedia: [RecipePreparationMediaRecord]
    let chatMessages: [ChatMessageRecord]

    init(context: ModelContext) throws {
        exportedAt = .now
        appSettings = try context.fetch(FetchDescriptor<AppSettings>()).map(AppSettingsRecord.init)
        categories = try context.fetch(FetchDescriptor<Category>()).map(CategoryRecord.init)
        pantryItems = try context.fetch(FetchDescriptor<PantryItem>()).map(PantryItemRecord.init)
        groceryItems = try context.fetch(FetchDescriptor<GroceryItem>()).map(GroceryItemRecord.init)
        utensilItems = try context.fetch(FetchDescriptor<UtensilItem>()).map(UtensilItemRecord.init)

        let recipeList = try context.fetch(FetchDescriptor<Recipe>())
        recipes = recipeList.map(RecipeRecord.init)
        recipeIngredients = recipeList
            .flatMap { $0.ingredients ?? [] }
            .map(RecipeIngredientRecord.init)
        recipeSteps = recipeList
            .flatMap { $0.steps ?? [] }
            .map(RecipeStepRecord.init)
        recipePreparationMedia = recipeList
            .flatMap { $0.preparationMedia ?? [] }
            .map(RecipePreparationMediaRecord.init)

        chatMessages = try context.fetch(FetchDescriptor<ChatMessage>()).map(ChatMessageRecord.init)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        appSettings = try container.decode([AppSettingsRecord].self, forKey: .appSettings)
        categories = try container.decode([CategoryRecord].self, forKey: .categories)
        pantryItems = try container.decode([PantryItemRecord].self, forKey: .pantryItems)
        groceryItems = try container.decode([GroceryItemRecord].self, forKey: .groceryItems)
        utensilItems = try container.decodeIfPresent([UtensilItemRecord].self, forKey: .utensilItems) ?? []
        recipes = try container.decode([RecipeRecord].self, forKey: .recipes)
        recipeIngredients = try container.decode([RecipeIngredientRecord].self, forKey: .recipeIngredients)
        recipeSteps = try container.decode([RecipeStepRecord].self, forKey: .recipeSteps)
        recipePreparationMedia = try container.decodeIfPresent([RecipePreparationMediaRecord].self, forKey: .recipePreparationMedia) ?? []
        chatMessages = try container.decode([ChatMessageRecord].self, forKey: .chatMessages)
    }

    func restore(into context: ModelContext) throws {
        try context.delete(model: Recipe.self)
        try context.delete(model: RecipePreparationMedia.self)
        try context.delete(model: PantryItem.self)
        try context.delete(model: GroceryItem.self)
        try context.delete(model: UtensilItem.self)
        try context.delete(model: Category.self)
        try context.delete(model: ChatMessage.self)
        try context.delete(model: AppSettings.self)

        for record in appSettings {
            let settings = AppSettings()
            settings.id = record.id
            settings.pantryDetailLevel = record.pantryDetailLevel
            settings.accentColorRaw = record.accentColorRaw
            settings.appearanceMode = record.appearanceMode
            settings.recipeViewMode = record.recipeViewMode
            settings.expiringItemsLeadDays = record.expiringItemsLeadDays
            settings.recipeCompatibilityThresholdPercentValue = record.recipeCompatibilityThresholdPercent
            settings.openAIAPIKey = record.openAIAPIKey
            settings.hasCompletedOnboarding = record.hasCompletedOnboarding
            settings.showUtensils = record.showUtensils
            context.insert(settings)
        }

        for record in categories {
            let category = Category(
                name: record.name,
                type: record.type,
                iconName: record.iconName,
                sortOrder: record.sortOrder
            )
            category.id = record.id
            context.insert(category)
        }

        for record in pantryItems {
            let item = PantryItem(
                name: record.name,
                descriptionText: record.descriptionText,
                imageData: record.imageData,
                category: record.category,
                quantity: record.quantity,
                unit: record.unit,
                iconName: record.iconName,
                isLinkedToGrocery: record.isLinkedToGrocery,
                expirationDate: record.expirationDate,
                sortOrder: record.sortOrder
            )
            item.id = record.id
            item.addedAt = record.addedAt
            context.insert(item)
        }

        for record in groceryItems {
            let item = GroceryItem(
                name: record.name,
                descriptionText: record.descriptionText,
                imageData: record.imageData,
                category: record.category,
                quantity: record.quantity,
                unit: record.unit,
                iconName: record.iconName,
                isChecked: record.isChecked,
                isFixed: record.isFixed,
                linkedPantryItemId: record.linkedPantryItemId,
                sortOrder: record.sortOrder
            )
            item.id = record.id
            item.addedAt = record.addedAt
            context.insert(item)
        }

        for record in utensilItems {
            let item = UtensilItem(
                name: record.name,
                descriptionText: record.descriptionText,
                imageData: record.imageData,
                category: record.category,
                iconName: record.iconName,
                sortOrder: record.sortOrder
            )
            item.id = record.id
            item.addedAt = record.addedAt
            context.insert(item)
        }

        var recipesByID: [UUID: Recipe] = [:]
        for record in recipes {
            let recipe = Recipe(
                name: record.name,
                descriptionText: record.descriptionText,
                imageData: record.imageData,
                externalURLString: record.externalURLString,
                category: record.category,
                tags: record.tags,
                prepTime: record.prepTime,
                cookTime: record.cookTime,
                servings: record.servings,
                calories: record.calories,
                difficulty: record.difficulty,
                isFavorite: record.isFavorite
            )
            recipe.id = record.id
            recipe.createdAt = record.createdAt
            recipe.updatedAt = record.updatedAt
            context.insert(recipe)
            recipesByID[record.id] = recipe
        }

        for record in recipeIngredients {
            guard let recipe = recipesByID[record.recipeID] else { continue }
            let ingredient = RecipeIngredient(
                name: record.name,
                quantity: record.quantity,
                unit: record.unit,
                preparationState: record.preparationState,
                iconName: record.iconName,
                sortOrder: record.sortOrder
            )
            ingredient.id = record.id
            ingredient.recipe = recipe
            context.insert(ingredient)
        }

        for record in recipeSteps {
            guard let recipe = recipesByID[record.recipeID] else { continue }
            let step = RecipeStep(order: record.order, instruction: record.instruction, durationMinutes: record.durationMinutes)
            step.id = record.id
            step.recipe = recipe
            context.insert(step)
        }

        for record in recipePreparationMedia {
            guard let recipe = recipesByID[record.recipeID] else { continue }
            let media = RecipePreparationMedia(
                mediaType: record.mediaType,
                data: record.data,
                fileExtension: record.fileExtension,
                sortOrder: record.sortOrder
            )
            media.id = record.id
            media.recipe = recipe
            context.insert(media)
        }

        for record in chatMessages {
            let message = ChatMessage(
                role: record.role,
                content: record.content,
                attachedRecipeIds: record.attachedRecipeIds,
                quickActions: record.quickActions
            )
            message.id = record.id
            message.timestamp = record.timestamp
            context.insert(message)
        }

        try context.save()
    }
}

// MARK: - Codable Records

struct AppSettingsRecord: Codable {
    let id: UUID
    let pantryDetailLevel: PantryDetailLevel
    let accentColorRaw: String
    let appearanceMode: AppearanceMode
    let recipeViewMode: RecipeViewMode
    let expiringItemsLeadDays: Int
    let recipeCompatibilityThresholdPercent: Int
    let openAIAPIKey: String
    let hasCompletedOnboarding: Bool
    let showUtensils: Bool

    init(_ settings: AppSettings) {
        id = settings.id
        pantryDetailLevel = settings.pantryDetailLevel
        accentColorRaw = settings.accentColorRaw
        appearanceMode = settings.appearanceMode
        recipeViewMode = settings.recipeViewMode
        expiringItemsLeadDays = settings.expiringItemsLeadDays
        recipeCompatibilityThresholdPercent = settings.recipeCompatibilityThresholdPercent
        openAIAPIKey = settings.openAIAPIKey
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        showUtensils = settings.showUtensils
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        pantryDetailLevel = try container.decode(PantryDetailLevel.self, forKey: .pantryDetailLevel)
        accentColorRaw = try container.decode(String.self, forKey: .accentColorRaw)
        appearanceMode = try container.decode(AppearanceMode.self, forKey: .appearanceMode)
        recipeViewMode = try container.decode(RecipeViewMode.self, forKey: .recipeViewMode)
        expiringItemsLeadDays = try container.decodeIfPresent(Int.self, forKey: .expiringItemsLeadDays) ?? 30
        recipeCompatibilityThresholdPercent = try container.decodeIfPresent(Int.self, forKey: .recipeCompatibilityThresholdPercent) ?? 80
        openAIAPIKey = try container.decode(String.self, forKey: .openAIAPIKey)
        hasCompletedOnboarding = try container.decode(Bool.self, forKey: .hasCompletedOnboarding)
        showUtensils = try container.decodeIfPresent(Bool.self, forKey: .showUtensils) ?? false
    }
}

struct CategoryRecord: Codable {
    let id: UUID
    let name: String
    let type: CategoryType
    let iconName: String?
    let sortOrder: Int

    init(_ category: Category) {
        id = category.id
        name = category.name
        type = category.type
        iconName = category.iconName
        sortOrder = category.sortOrder
    }
}

struct PantryItemRecord: Codable {
    let id: UUID
    let name: String
    let descriptionText: String
    let imageData: Data?
    let category: String
    let quantity: Double?
    let unit: String?
    let iconName: String?
    let isLinkedToGrocery: Bool
    let expirationDate: Date?
    let sortOrder: Int
    let addedAt: Date

    init(_ item: PantryItem) {
        id = item.id
        name = item.name
        descriptionText = item.descriptionText
        imageData = item.imageData
        category = item.category
        quantity = item.quantity
        unit = item.unit
        iconName = item.iconName
        isLinkedToGrocery = item.isLinkedToGrocery
        expirationDate = item.expirationDate
        sortOrder = item.sortOrder
        addedAt = item.addedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        descriptionText = try container.decodeIfPresent(String.self, forKey: .descriptionText) ?? ""
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        category = try container.decode(String.self, forKey: .category)
        quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        isLinkedToGrocery = try container.decode(Bool.self, forKey: .isLinkedToGrocery)
        expirationDate = try container.decodeIfPresent(Date.self, forKey: .expirationDate)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        addedAt = try container.decode(Date.self, forKey: .addedAt)
    }
}

struct GroceryItemRecord: Codable {
    let id: UUID
    let name: String
    let descriptionText: String
    let imageData: Data?
    let category: String
    let quantity: Double?
    let unit: String?
    let iconName: String?
    let isChecked: Bool
    let isFixed: Bool
    let linkedPantryItemId: UUID?
    let sortOrder: Int
    let addedAt: Date

    init(_ item: GroceryItem) {
        id = item.id
        name = item.name
        descriptionText = item.descriptionText
        imageData = item.imageData
        category = item.category
        quantity = item.quantity
        unit = item.unit
        iconName = item.iconName
        isChecked = item.isChecked
        isFixed = item.isFixed
        linkedPantryItemId = item.linkedPantryItemId
        sortOrder = item.sortOrder
        addedAt = item.addedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        descriptionText = try container.decodeIfPresent(String.self, forKey: .descriptionText) ?? ""
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        category = try container.decode(String.self, forKey: .category)
        quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        isChecked = try container.decodeIfPresent(Bool.self, forKey: .isChecked) ?? false
        isFixed = try container.decodeIfPresent(Bool.self, forKey: .isFixed) ?? false
        linkedPantryItemId = try container.decodeIfPresent(UUID.self, forKey: .linkedPantryItemId)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        addedAt = try container.decode(Date.self, forKey: .addedAt)
    }
}

struct UtensilItemRecord: Codable {
    let id: UUID
    let name: String
    let descriptionText: String
    let imageData: Data?
    let category: String
    let iconName: String?
    let sortOrder: Int
    let addedAt: Date

    init(_ item: UtensilItem) {
        id = item.id
        name = item.name
        descriptionText = item.descriptionText
        imageData = item.imageData
        category = item.category
        iconName = item.iconName
        sortOrder = item.sortOrder
        addedAt = item.addedAt
    }
}

struct RecipeRecord: Codable {
    let id: UUID
    let name: String
    let descriptionText: String
    let imageData: Data?
    let category: String
    let tags: [String]
    let prepTime: Int
    let cookTime: Int
    let servings: Int
    let calories: Int?
    let difficulty: Difficulty
    let isFavorite: Bool
    let externalURLString: String
    let createdAt: Date
    let updatedAt: Date

    init(_ recipe: Recipe) {
        id = recipe.id
        name = recipe.name
        descriptionText = recipe.descriptionText
        imageData = recipe.imageData
        category = recipe.category
        tags = recipe.tags
        prepTime = recipe.prepTime
        cookTime = recipe.cookTime
        servings = recipe.servings
        calories = recipe.calories
        difficulty = recipe.difficulty
        isFavorite = recipe.isFavorite
        externalURLString = recipe.externalURLString
        createdAt = recipe.createdAt
        updatedAt = recipe.updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        descriptionText = try container.decode(String.self, forKey: .descriptionText)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        category = try container.decode(String.self, forKey: .category)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        prepTime = try container.decodeIfPresent(Int.self, forKey: .prepTime) ?? 0
        cookTime = try container.decodeIfPresent(Int.self, forKey: .cookTime) ?? 0
        servings = try container.decodeIfPresent(Int.self, forKey: .servings) ?? 1
        calories = try container.decodeIfPresent(Int.self, forKey: .calories)
        difficulty = try container.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? .easy
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        externalURLString = try container.decodeIfPresent(String.self, forKey: .externalURLString) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct RecipePreparationMediaRecord: Codable {
    let id: UUID
    let recipeID: UUID
    let mediaType: RecipePreparationMediaType
    let data: Data
    let fileExtension: String
    let sortOrder: Int

    init(_ media: RecipePreparationMedia) {
        id = media.id
        recipeID = media.recipe?.id ?? UUID()
        mediaType = media.mediaType
        data = media.data
        fileExtension = media.fileExtension
        sortOrder = media.sortOrder
    }
}

struct RecipeIngredientRecord: Codable {
    let id: UUID
    let recipeID: UUID
    let name: String
    let quantity: Double?
    let unit: String
    let preparationState: String
    let iconName: String?
    let sortOrder: Int

    init(_ ingredient: RecipeIngredient) {
        id = ingredient.id
        recipeID = ingredient.recipe?.id ?? UUID()
        name = ingredient.name
        quantity = ingredient.quantity
        unit = ingredient.unit
        preparationState = ingredient.preparationState
        iconName = ingredient.iconName
        sortOrder = ingredient.sortOrder
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        recipeID = try container.decode(UUID.self, forKey: .recipeID)
        name = try container.decode(String.self, forKey: .name)
        quantity = try container.decodeIfPresent(Double.self, forKey: .quantity)
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        preparationState = try container.decodeIfPresent(String.self, forKey: .preparationState) ?? ""
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
    }
}

struct RecipeStepRecord: Codable {
    let id: UUID
    let recipeID: UUID
    let order: Int
    let instruction: String
    let durationMinutes: Int?

    init(_ step: RecipeStep) {
        id = step.id
        recipeID = step.recipe?.id ?? UUID()
        order = step.order
        instruction = step.instruction
        durationMinutes = step.durationMinutes
    }
}

struct ChatMessageRecord: Codable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    let attachedRecipeIds: [UUID]
    let quickActions: [QuickAction]

    init(_ message: ChatMessage) {
        id = message.id
        role = message.role
        content = message.content
        timestamp = message.timestamp
        attachedRecipeIds = message.attachedRecipeIds
        quickActions = message.quickActions
    }
}

// MARK: - Simple Zip Archive (reused from original)

enum SimpleZipArchive {
    static func archive(fileName: String, data: Data) throws -> Data {
        guard let nameData = fileName.data(using: .utf8) else {
            throw BackupTransferError.invalidFileName
        }
        guard nameData.count <= Int(UInt16.max), data.count <= Int(UInt32.max) else {
            throw BackupTransferError.payloadTooLarge
        }

        let crc = CRC32.checksum(of: data)
        var archive = Data()

        archive.appendUInt32(0x04034B50)
        archive.appendUInt16(20)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt32(crc)
        archive.appendUInt32(UInt32(data.count))
        archive.appendUInt32(UInt32(data.count))
        archive.appendUInt16(UInt16(nameData.count))
        archive.appendUInt16(0)
        archive.append(nameData)
        archive.append(data)

        let centralDirectoryOffset = UInt32(archive.count)

        archive.appendUInt32(0x02014B50)
        archive.appendUInt16(20)
        archive.appendUInt16(20)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt32(crc)
        archive.appendUInt32(UInt32(data.count))
        archive.appendUInt32(UInt32(data.count))
        archive.appendUInt16(UInt16(nameData.count))
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt32(0)
        archive.appendUInt32(0)
        archive.append(nameData)

        let centralDirectorySize = UInt32(archive.count) - centralDirectoryOffset

        archive.appendUInt32(0x06054B50)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(1)
        archive.appendUInt16(1)
        archive.appendUInt32(centralDirectorySize)
        archive.appendUInt32(centralDirectoryOffset)
        archive.appendUInt16(0)

        return archive
    }

    static func extractFile(named fileName: String, from archive: Data) throws -> Data {
        var offset = 0

        while offset + 30 <= archive.count {
            let signature = try archive.readUInt32(at: offset)

            if signature == 0x04034B50 {
                let compressionMethod = try archive.readUInt16(at: offset + 8)
                guard compressionMethod == 0 else {
                    throw BackupTransferError.unsupportedZipCompression
                }

                let payloadSize = Int(try archive.readUInt32(at: offset + 18))
                let nameLength = Int(try archive.readUInt16(at: offset + 26))
                let extraLength = Int(try archive.readUInt16(at: offset + 28))
                let nameStart = offset + 30
                let nameEnd = nameStart + nameLength
                let dataStart = nameEnd + extraLength
                let dataEnd = dataStart + payloadSize

                guard dataEnd <= archive.count else {
                    throw BackupTransferError.invalidArchive
                }

                let entryNameData = archive.subdata(in: nameStart..<nameEnd)
                let entryName = String(data: entryNameData, encoding: .utf8)

                if entryName == fileName {
                    return archive.subdata(in: dataStart..<dataEnd)
                }

                offset = dataEnd
            } else if signature == 0x02014B50 || signature == 0x06054B50 {
                break
            } else {
                throw BackupTransferError.invalidArchive
            }
        }

        throw BackupTransferError.missingBackupPayload
    }
}

enum BackupTransferError: LocalizedError {
    case invalidFileName
    case payloadTooLarge
    case invalidArchive
    case unsupportedZipCompression
    case missingBackupPayload

    var errorDescription: String? {
        switch self {
        case .invalidFileName:
            "Nome do arquivo de backup inválido."
        case .payloadTooLarge:
            "O backup é grande demais para ser compactado neste formato."
        case .invalidArchive:
            "O arquivo .zip selecionado é inválido."
        case .unsupportedZipCompression:
            "O arquivo .zip usa um tipo de compactação não suportado por este app."
        case .missingBackupPayload:
            "O arquivo .zip não contém um backup válido do Smart Kitchen."
        }
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = 0xEDB88320 ^ (crc >> 1)
            } else {
                crc >>= 1
            }
        }
        return crc
    }

    static func checksum(of data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { buffer in
            append(buffer.bindMemory(to: UInt8.self))
        }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { buffer in
            append(buffer.bindMemory(to: UInt8.self))
        }
    }

    func readUInt16(at offset: Int) throws -> UInt16 {
        guard offset + 2 <= count else {
            throw BackupTransferError.invalidArchive
        }
        return subdata(in: offset..<(offset + 2)).withUnsafeBytes {
            UInt16(littleEndian: $0.load(as: UInt16.self))
        }
    }

    func readUInt32(at offset: Int) throws -> UInt32 {
        guard offset + 4 <= count else {
            throw BackupTransferError.invalidArchive
        }
        return subdata(in: offset..<(offset + 4)).withUnsafeBytes {
            UInt32(littleEndian: $0.load(as: UInt32.self))
        }
    }
}
