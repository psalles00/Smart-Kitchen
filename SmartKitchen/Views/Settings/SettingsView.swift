import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsArray: [AppSettings]

    @State private var exportDocument = BackupZipDocument(data: Data())
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    private var settings: AppSettings? { settingsArray.first }
    private var backupFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return "SmartKitchen-Backup-\(formatter.string(from: .now))"
    }

    var body: some View {
        Form {
            // MARK: - Geral
            Section("Geral") {
                if let settings {
                    Picker("Aparência", selection: Binding(
                        get: { settings.appearanceMode },
                        set: { settings.appearanceMode = $0 }
                    )) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Picker("Cor de destaque", selection: Binding(
                        get: { settings.accentColorChoice },
                        set: { settings.accentColorChoice = $0 }
                    )) {
                        ForEach(AccentColorChoice.allCases) { choice in
                            Label {
                                Text(choice.displayName)
                            } icon: {
                                Circle()
                                    .fill(choice.color)
                                    .frame(width: 14, height: 14)
                            }
                            .tag(choice)
                        }
                    }
                }
            }

            // MARK: - Assistente
            Section("Assistente") {
                LabeledContent("Modelo IA") {
                    Text("GPT-4.1 mini")
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Listas
            Section("Listas") {
                if let settings {
                    Picker("Modo da despensa", selection: Binding(
                        get: { settings.pantryDetailLevel },
                        set: { settings.pantryDetailLevel = $0 }
                    )) {
                        ForEach(PantryDetailLevel.allCases) { level in
                            Text(level.displayName).tag(level)
                        }
                    }

                    Stepper(
                        "Avisar validade com \(settings.expiringItemsLeadDays) dias de antecedência",
                        value: Binding(
                            get: { settings.expiringItemsLeadDays },
                            set: { settings.expiringItemsLeadDays = $0 }
                        ),
                        in: 1...180
                    )
                }
            }

            // MARK: - Receitas
            Section("Receitas") {
                if let settings {
                    Picker("Visualização padrão", selection: Binding(
                        get: { settings.recipeViewMode },
                        set: { settings.recipeViewMode = $0 }
                    )) {
                        ForEach(RecipeViewMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.icon).tag(mode)
                        }
                    }

                    Stepper(
                        "Compatível a partir de \(settings.recipeCompatibilityThresholdPercent)%",
                        value: Binding(
                            get: { settings.recipeCompatibilityThresholdPercent },
                            set: { settings.recipeCompatibilityThresholdPercent = $0 }
                        ),
                        in: 10...100,
                        step: 5
                    )
                }
            }

            // MARK: - Dados
            Section("Dados") {
                Button("Exportar backup (.zip)", systemImage: "square.and.arrow.up") {
                    exportBackup()
                }

                Button("Importar backup (.zip)", systemImage: "square.and.arrow.down") {
                    isImportingBackup = true
                }

                Button("Restaurar dados de demonstração", role: .destructive) {
                    resetData()
                }
            }

            // MARK: - Sobre
            Section("Sobre") {
                LabeledContent("Versão") {
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Desenvolvido com") {
                    Text("SwiftUI + SwiftData")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Configurações")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("OK") { dismiss() }
            }
        }
        .fileExporter(
            isPresented: $isExportingBackup,
            document: exportDocument,
            contentType: .smartKitchenZip,
            defaultFilename: backupFileName
        ) { result in
            if case .failure(let error) = result {
                presentAlert(title: "Falha ao exportar", message: error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [.smartKitchenZip]
        ) { result in
            switch result {
            case .success(let url):
                importBackup(from: url)
            case .failure(let error):
                presentAlert(title: "Falha ao importar", message: error.localizedDescription)
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func resetData() {
        // Delete all existing data
        try? modelContext.delete(model: Recipe.self)
        try? modelContext.delete(model: PantryItem.self)
        try? modelContext.delete(model: GroceryItem.self)
        try? modelContext.delete(model: Category.self)
        try? modelContext.delete(model: ChatMessage.self)
        try? modelContext.delete(model: AppSettings.self)
        // Re-seed
        DataSeeder.seedIfNeeded(context: modelContext)
        try? modelContext.save()
    }

    private func exportBackup() {
        do {
            exportDocument = BackupZipDocument(data: try BackupTransferService.exportArchive(from: modelContext))
            isExportingBackup = true
        } catch {
            presentAlert(title: "Falha ao exportar", message: error.localizedDescription)
        }
    }

    private func importBackup(from url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try BackupTransferService.importArchive(data, into: modelContext)
            presentAlert(title: "Backup importado", message: "Os dados do aplicativo foram restaurados com sucesso.")
        } catch {
            presentAlert(title: "Falha ao importar", message: error.localizedDescription)
        }
    }

    private func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}

private struct BackupZipDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.smartKitchenZip] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private enum BackupTransferService {
    private static let payloadFileName = "smart-kitchen-backup.json"

    static func exportArchive(from context: ModelContext) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let snapshot = try AppBackupSnapshot(context: context)
        let data = try encoder.encode(snapshot)
        return try SimpleZipArchive.archive(fileName: payloadFileName, data: data)
    }

    static func importArchive(_ archiveData: Data, into context: ModelContext) throws {
        let jsonData = try SimpleZipArchive.extractFile(named: payloadFileName, from: archiveData)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(AppBackupSnapshot.self, from: jsonData)
        try snapshot.restore(into: context)
    }
}

private struct AppBackupSnapshot: Codable {
    let exportedAt: Date
    let appSettings: [AppSettingsRecord]
    let categories: [CategoryRecord]
    let pantryItems: [PantryItemRecord]
    let groceryItems: [GroceryItemRecord]
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

        let recipeList = try context.fetch(FetchDescriptor<Recipe>())
        recipes = recipeList.map(RecipeRecord.init)
        recipeIngredients = recipeList
            .flatMap { $0.ingredients }
            .map(RecipeIngredientRecord.init)
        recipeSteps = recipeList
            .flatMap { $0.steps }
            .map(RecipeStepRecord.init)
        recipePreparationMedia = recipeList
            .flatMap { $0.preparationMedia }
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

private struct AppSettingsRecord: Codable {
    let id: UUID
    let pantryDetailLevel: PantryDetailLevel
    let accentColorRaw: String
    let appearanceMode: AppearanceMode
    let recipeViewMode: RecipeViewMode
    let expiringItemsLeadDays: Int
    let recipeCompatibilityThresholdPercent: Int
    let openAIAPIKey: String
    let hasCompletedOnboarding: Bool

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
    }
}

private struct CategoryRecord: Codable {
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

private struct PantryItemRecord: Codable {
    let id: UUID
    let name: String
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

private struct GroceryItemRecord: Codable {
    let id: UUID
    let name: String
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
}

private struct RecipeRecord: Codable {
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

private struct RecipePreparationMediaRecord: Codable {
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

private struct RecipeIngredientRecord: Codable {
    let id: UUID
    let recipeID: UUID
    let name: String
    let quantity: Double?
    let unit: String
    let iconName: String?
    let sortOrder: Int

    init(_ ingredient: RecipeIngredient) {
        id = ingredient.id
        recipeID = ingredient.recipe?.id ?? UUID()
        name = ingredient.name
        quantity = ingredient.quantity
        unit = ingredient.unit
        iconName = ingredient.iconName
        sortOrder = ingredient.sortOrder
    }
}

private struct RecipeStepRecord: Codable {
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

private struct ChatMessageRecord: Codable {
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

private enum SimpleZipArchive {
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

private enum BackupTransferError: LocalizedError {
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

private enum CRC32 {
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

private extension Data {
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

private extension UTType {
    static let smartKitchenZip = UTType(filenameExtension: "zip") ?? .data
}
