import Foundation
import AVFoundation

/// Transforms unstructured text (pasted, OCR'd, scraped) into a `RecipeDraft`
/// using the best available language model.
///
/// Strategy:
///   1. If Apple FoundationModels is available (iOS 26 + Apple Intelligence),
///      use `LanguageModelSession` with a `@Generable` schema — on-device,
///      private, free. (Wired up in Fase 5; currently returns nil so we fall back.)
///   2. Fallback to OpenAI gpt-4.1-mini via the existing `AIService`.
///
/// The AI is instructed to use only the canonical unit/state labels from
/// `RecipeOptionCatalog` so downstream normalization is cheap.
@MainActor
struct RecipeStructurer {

    let aiService: AIService
    let apiKey: String

    init(aiService: AIService = AIService(), apiKey: String = APIConfig.openAIAPIKey) {
        self.aiService = aiService
        self.apiKey = apiKey
    }

    /// Structure the given raw text into a draft recipe.
    /// - Parameters:
    ///   - text: raw text (caption, OCR output, paste, scraped body). Already cleaned of HTML.
    ///   - hints: known metadata to seed the draft (title, source URL, cover image URL…).
    func structure(text: String, hints: Hints = .init()) async throws -> RecipeDraft {
        RecipeImportLogger.info("structurer start textChars=\(text.count) sourceLabel=\(hints.sourceLabel)")
        // 1. Try on-device Foundation Models (Fase 5 will implement; no-op for now).
        if let draft = try await structureOnDevice(text: text, hints: hints) {
            RecipeImportLogger.info("structurer used on-device model")
            return merge(draft: draft, hints: hints)
        }
        RecipeImportLogger.info("structurer fallback to OpenAI")

        // 2. OpenAI fallback.
        let draft = try await structureWithOpenAI(text: text, hints: hints)
        RecipeImportLogger.info("structurer OpenAI produced \(RecipeImportLogger.draftSummary(draft))")
        return merge(draft: draft, hints: hints)
    }

    // MARK: - Hints

    struct Hints {
        var title: String? = nil
        var description: String? = nil
        var externalURL: URL? = nil
        var imageURL: URL? = nil
        var sourceLabel: String = ""
    }

    // MARK: - On-device (Fase 5: Apple Foundation Models)

    private func structureOnDevice(text: String, hints: Hints) async throws -> RecipeDraft? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            RecipeImportLogger.debug("structurer trying FoundationModels")
            return try await structureOnDeviceFoundationModels(text: text, hints: hints)
        }
        #endif
        RecipeImportLogger.debug("structurer FoundationModels unavailable")
        return nil
    }

    // MARK: - OpenAI

    private func structureWithOpenAI(text: String, hints: Hints) async throws -> RecipeDraft {
        let systemPrompt = Self.systemPrompt
        let userPrompt = Self.userPrompt(text: text, hints: hints)
        RecipeImportLogger.debug("openai prompts systemChars=\(systemPrompt.count) userChars=\(userPrompt.count)")

        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]

        // Force JSON output using the tool definition pattern.
        let tool: [[String: Any]] = [[
            "type": "function",
            "function": [
                "name": "emit_recipe",
                "description": "Retorna a receita estruturada.",
                "parameters": Self.jsonSchema
            ]
        ]]

        // Nudge the model to call the tool.
        messages.append([
            "role": "user",
            "content": "Chame a função emit_recipe com a receita estruturada. Não envie texto fora da chamada."
        ])

        let response = try await aiService.sendChat(messages: messages, tools: tool, apiKey: apiKey)
        RecipeImportLogger.info("openai response toolCalls=\(response.toolCalls.count) contentChars=\((response.content ?? "").count)")

        guard let call = response.toolCalls.first else {
            // Sometimes models return JSON in content instead; try to parse that.
            if let content = response.content, let data = content.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                RecipeImportLogger.debug("openai parsed response from content JSON")
                return parse(dict: dict)
            }
            RecipeImportLogger.error("openai returned no tool call and no JSON content")
            throw RecipeImportError.aiFailed("A resposta do modelo não contém dados estruturados.")
        }

        guard let data = call.argumentsJSON.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            RecipeImportLogger.error("openai tool arguments invalid JSON")
            throw RecipeImportError.aiFailed("Argumentos da função em formato inválido.")
        }

        RecipeImportLogger.debug("openai tool arguments parsed keys=\(dict.keys.sorted().joined(separator: ","))")
        return parse(dict: dict)
    }

    // MARK: - Parsing

    private func parse(dict: [String: Any]) -> RecipeDraft {
        RecipeImportLogger.debug("parse start keys=\(dict.keys.sorted().joined(separator: ","))")
        var d = RecipeDraft()
        if let s = dict["name"] as? String { d.name = s.trimmingCharacters(in: .whitespacesAndNewlines); d.nameConfidence = .high }
        if let s = dict["description"] as? String { d.descriptionText = s.trimmingCharacters(in: .whitespacesAndNewlines); d.descriptionConfidence = s.isEmpty ? .low : .medium }
        if let s = dict["category"] as? String, !s.isEmpty {
            d.category = s
            d.categoryConfidence = .medium
        }
        if let difficulty = dict["difficulty"] as? String,
           let matched = Difficulty.allCases.first(where: {
               $0.rawValue.compare(difficulty, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
           }) {
            d.difficulty = matched
        }
        if let v = dict["prep_time_minutes"] as? Int, v > 0 {
            d.prepTime = v
            d.prepTimeConfidence = .high
        }
        if let v = dict["cook_time_minutes"] as? Int, v > 0 {
            d.cookTime = v
            d.cookTimeConfidence = .high
        }
        if let v = dict["servings"] as? Int, v > 0 {
            d.servings = v
            d.servingsConfidence = .high
        }
        if let v = dict["calories"] as? Int { d.calories = v }
        if let utensils = dict["required_utensils"] as? [String] {
            d.requiredUtensils = utensils.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        if let ingredients = dict["ingredients"] as? [[String: Any]] {
            d.ingredients = ingredients.enumerated().compactMap { _, item in
                guard let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty else { return nil }
                let qty: Double? = {
                    if let n = item["quantity"] as? Double { return n }
                    if let n = item["quantity"] as? Int { return Double(n) }
                    if let s = item["quantity"] as? String, let n = Double(s.replacingOccurrences(of: ",", with: ".")) { return n }
                    return nil
                }()
                let unit = (item["unit"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                let state = (item["state"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                let conf = confidenceString(item["confidence"] as? String) ?? .medium
                return IngredientDraft(
                    name: name,
                    quantity: qty,
                    unit: unit,
                    preparationState: state,
                    confidence: conf,
                    sectionID: nil
                )
            }
            RecipeImportLogger.debug("parse ingredients count=\(d.ingredients.count)")
        }

        if let sectionsArray = dict["ingredient_sections"] as? [[String: Any]] {
            var order = 0
            for item in sectionsArray {
                let rawTitle = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let rawSubtitle = (item["subtitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let rawItems = item["ingredients"] as? [[String: Any]] ?? []
                // Skip a section that has no title AND no ingredients at all.
                if rawTitle.isEmpty && rawItems.isEmpty { continue }
                let sectionID = UUID()
                d.ingredientSections.append(
                    SectionDraft(id: sectionID, title: rawTitle, subtitle: rawSubtitle, sortOrder: order)
                )
                order += 1
                for raw in rawItems {
                    guard let name = (raw["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !name.isEmpty else { continue }
                    let qty: Double? = {
                        if let n = raw["quantity"] as? Double { return n }
                        if let n = raw["quantity"] as? Int { return Double(n) }
                        if let s = raw["quantity"] as? String, let n = Double(s.replacingOccurrences(of: ",", with: ".")) { return n }
                        return nil
                    }()
                    let unit = (raw["unit"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                    let state = (raw["state"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                    let conf = confidenceString(raw["confidence"] as? String) ?? .medium
                    d.ingredients.append(
                        IngredientDraft(
                            name: name,
                            quantity: qty,
                            unit: unit,
                            preparationState: state,
                            confidence: conf,
                            sectionID: sectionID
                        )
                    )
                }
            }
            RecipeImportLogger.debug("parse sections count=\(d.ingredientSections.count) totalIngredients=\(d.ingredients.count)")
        }

        if let steps = dict["steps"] as? [[String: Any]] {
            d.steps = steps.enumerated().compactMap { index, item in
                let instruction = (item["instruction"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !instruction.isEmpty else { return nil }
                let order = (item["order"] as? Int) ?? (index + 1)
                let duration = item["duration_minutes"] as? Int
                let conf = confidenceString(item["confidence"] as? String) ?? .medium
                return StepDraft(order: order, instruction: instruction, durationMinutes: duration, confidence: conf)
            }
            RecipeImportLogger.debug("parse steps count=\(d.steps.count)")
        }

        RecipeImportLogger.info("parse completed \(RecipeImportLogger.draftSummary(d))")
        return d
    }

    private func confidenceString(_ raw: String?) -> FieldConfidence? {
        switch raw?.lowercased() {
        case "high", "alta":   return .high
        case "medium", "média", "media": return .medium
        case "low", "baixa":   return .low
        default:                return nil
        }
    }

    // MARK: - Merge hints

    private func merge(draft: RecipeDraft, hints: Hints) -> RecipeDraft {
        var d = draft
        if d.name.isEmpty, let t = hints.title {
            d.name = t
            d.nameConfidence = .medium
        }
        if d.descriptionText.isEmpty, let desc = hints.description {
            d.descriptionText = desc
            d.descriptionConfidence = .medium
        }
        if d.imageURL == nil { d.imageURL = hints.imageURL }
        if d.externalURLString.isEmpty, let url = hints.externalURL { d.externalURLString = url.absoluteString }
        if d.sourceLabel.isEmpty { d.sourceLabel = hints.sourceLabel }
        RecipeImportLogger.debug("merge hints completed \(RecipeImportLogger.draftSummary(d))")
        return d
    }

    // MARK: - Prompts & schema

    private static var unitLabels: [String] {
        RecipeOptionCatalog.unitOptions.map { $0.menuLabel }
    }
    private static var stateLabels: [String] {
        RecipeOptionCatalog.stateOptions.map { $0.menuLabel }
    }

    static let systemPrompt: String = """
    Você é um assistente especializado em estruturar receitas culinárias em português brasileiro.
    Receba o texto de uma receita (pode estar bagunçado, vir de OCR, legenda de rede social ou texto colado) e transforme-a em dados estruturados.

    Regras:
    - Preserve as quantidades exatas do texto original sempre que possível.
    - Se uma quantidade não estiver clara, deixe o campo vazio e marque confiança "low" para o ingrediente.
    - Use apenas unidades desta lista (campo unit): \(unitLabels.joined(separator: " | ")).
      Você pode escolher a abreviação (ex.: "g", "mL", "c.s.") ou o nome completo. Se a unidade no texto não encaixar, deixe vazio.
    - Use apenas estados desta lista (campo state): \(stateLabels.joined(separator: " | ")). Se o texto não mencionar estado, deixe vazio.
    - Separe quantidade + unidade + nome + estado do ingrediente. Exemplo: "2 xícaras de farinha peneirada" → quantity=2, unit="Xícara", name="Farinha", state="Peneirada".
    - AGRUPAMENTO DE INGREDIENTES: quando a receita apresentar blocos como "Para a massa", "Para o creme", "Para a calda", "Recheio", "Para a marinada", "Ingredientes secos", etc., crie uma entrada em "ingredient_sections" com title obrigatório (ex.: "Para a massa") e agrupe os ingredientes daquele bloco dentro do array "ingredients" da seção.
    - NOTAS DE BLOCO: qualquer observação adjacente ao título do bloco (rendimento, temperatura, tempo, dica) deve ir em "subtitle" da seção. Nunca descarte notas do autor.
    - Ingredientes que aparecem antes de qualquer bloco nomeado ou quando a receita não tem blocos devem ficar no array "ingredients" no nível superior (sem seção).
    - Quando só houver um bloco implícito, prefira deixar tudo no array de nível superior sem criar seção artificial.
    - Passos devem ser curtos, imperativos e numerados.
    - Categoria: prefira "Café da manhã", "Almoço", "Jantar", "Lanche", "Sobremesa", "Bebida" ou "Outros". Se nenhuma servir claramente, proponha um nome curto e natural em português.
    - Dificuldade: "Fácil", "Médio" ou "Difícil".
    - Não invente ingredientes nem passos. Se o texto for insuficiente, devolva arrays vazios.
    - Preserve o idioma do texto original (provavelmente pt-BR).
    - Não use emojis, hashtags ou texto promocional no resultado.
    """

    static func userPrompt(text: String, hints: Hints) -> String {
        var parts = ["Texto da receita:\n\"\"\"\n\(text)\n\"\"\""]
        if let t = hints.title, !t.isEmpty {
            parts.append("Título sugerido da fonte: \(t)")
        }
        if let d = hints.description, !d.isEmpty {
            parts.append("Descrição da fonte: \(d)")
        }
        if let url = hints.externalURL {
            parts.append("URL original: \(url.absoluteString)")
        }
        return parts.joined(separator: "\n\n")
    }

    static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "name":           ["type": "string", "description": "Nome da receita."],
            "description":    ["type": "string"],
            "category":       ["type": "string"],
            "difficulty":     ["type": "string", "enum": ["Fácil", "Médio", "Difícil"]],
            "prep_time_minutes": ["type": "integer", "minimum": 0],
            "cook_time_minutes": ["type": "integer", "minimum": 0],
            "servings":       ["type": "integer", "minimum": 1],
            "calories":       ["type": "integer", "minimum": 0],
            "required_utensils": [
                "type": "array",
                "items": ["type": "string"]
            ],
            "ingredients": [
                "type": "array",
                "description": "Ingredientes sem seção (top-level). Use este array quando a receita NÃO tiver blocos rotulados.",
                "items": [
                    "type": "object",
                    "properties": [
                        "name":       ["type": "string"],
                        "quantity":   ["type": ["number", "null"]],
                        "unit":       ["type": "string"],
                        "state":      ["type": "string"],
                        "confidence": ["type": "string", "enum": ["high", "medium", "low"]]
                    ],
                    "required": ["name"]
                ]
            ],
            "ingredient_sections": [
                "type": "array",
                "description": "Blocos rotulados de ingredientes (ex.: 'Para a massa', 'Para o creme'). Use subtitle para notas/observações do bloco.",
                "items": [
                    "type": "object",
                    "properties": [
                        "title":    ["type": "string"],
                        "subtitle": ["type": "string"],
                        "ingredients": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "name":       ["type": "string"],
                                    "quantity":   ["type": ["number", "null"]],
                                    "unit":       ["type": "string"],
                                    "state":      ["type": "string"],
                                    "confidence": ["type": "string", "enum": ["high", "medium", "low"]]
                                ],
                                "required": ["name"]
                            ]
                        ]
                    ],
                    "required": ["title", "ingredients"]
                ]
            ],
            "steps": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "order":       ["type": "integer", "minimum": 1],
                        "instruction": ["type": "string"],
                        "duration_minutes": ["type": ["integer", "null"]],
                        "confidence": ["type": "string", "enum": ["high", "medium", "low"]]
                    ],
                    "required": ["instruction"]
                ]
            ]
        ],
        "required": ["name", "steps"]
    ]
}

@MainActor
final class RecipeImportImprover {
    private let aiService: AIService
    private let apiKey: String

    init(aiService: AIService = AIService(), apiKey: String = APIConfig.openAIAPIKey) {
        self.aiService = aiService
        self.apiKey = apiKey
    }

    func improve(draft: RecipeDraft) async throws -> RecipeDraft {
        guard !apiKey.isEmpty else {
            throw RecipeImportError.aiFailed("Chave da OpenAI não configurada para melhorar a importação.")
        }

        let sourceURL = URL(string: draft.externalURLString)
        var videoURL: URL? = draft.videoURL ?? directVideoURL(from: draft.externalURLString)
        if videoURL == nil, let source = sourceURL {
            videoURL = try? await resolveVideoURL(from: source)
        }

        guard let resolvedVideoURL = videoURL else {
            throw RecipeImportError.unsupportedSource("Não foi possível localizar um link direto de vídeo para transcrição.")
        }

        RecipeImportLogger.info("improver start videoURL=\(resolvedVideoURL.absoluteString)")

        let videoFileURL = try await downloadVideo(from: resolvedVideoURL, referer: sourceURL)
        defer { try? FileManager.default.removeItem(at: videoFileURL) }

        let audioFileURL = try await extractAudio(from: videoFileURL)
        defer { try? FileManager.default.removeItem(at: audioFileURL) }

        let transcript = try await transcribeAudio(fileURL: audioFileURL)
        RecipeImportLogger.info("improver transcript chars=\(transcript.count)")

        let structurer = RecipeStructurer(aiService: aiService, apiKey: apiKey)
        let combinedInput = makeCombinedInput(draft: draft, transcript: transcript)
        var improved = try await structurer.structure(
            text: combinedInput,
            hints: .init(
                title: draft.name,
                description: draft.descriptionText,
                externalURL: URL(string: draft.externalURLString),
                imageURL: draft.imageURL,
                sourceLabel: draft.sourceLabel.isEmpty ? "Importação refinada" : draft.sourceLabel
            )
        )

        if improved.imageData == nil {
            improved.imageData = draft.imageData
        }
        if improved.imageURL == nil {
            improved.imageURL = draft.imageURL
        }
        if improved.videoURL == nil {
            improved.videoURL = draft.videoURL ?? resolvedVideoURL
        }
        if improved.externalURLString.isEmpty {
            improved.externalURLString = draft.externalURLString
        }

        improved.ingredients = mergeDuplicateIngredients(improved.ingredients)
        RecipeImportLogger.info("improver completed \(RecipeImportLogger.draftSummary(improved))")
        return improved
    }

    private func makeCombinedInput(draft: RecipeDraft, transcript: String) -> String {
        let description = draft.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let ingredientSnapshot = draft.ingredients
            .map { item in
                var parts: [String] = []
                parts.append(item.name)
                if let q = item.quantity {
                    parts.append(String(q))
                }
                if !item.unit.isEmpty {
                    parts.append(item.unit)
                }
                if !item.preparationState.isEmpty {
                    parts.append(item.preparationState)
                }
                return parts.joined(separator: " ")
            }
            .joined(separator: "\n")

        return """
        DESCRICAO DA RECEITA:
        \(description)

        INGREDIENTES EXTRAIDOS (podem estar duplicados):
        \(ingredientSnapshot)

        TRANSCRICAO DO VIDEO:
        \(transcript)
        """
    }

    private func downloadVideo(from url: URL, referer: URL? = nil) async throws -> URL {
        RecipeImportLogger.debug("improver download video")
        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }

        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RecipeImportError.fetchFailed("Falha ao baixar vídeo para transcrição.")
        }

        let finalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-video-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: finalURL)
        try FileManager.default.moveItem(at: tempURL, to: finalURL)

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? NSNumber)?.intValue ?? 0
        RecipeImportLogger.debug("improver video downloaded bytes=\(fileSize)")
        return finalURL
    }

    private func extractAudio(from videoURL: URL) async throws -> URL {
        RecipeImportLogger.debug("improver extract audio")
        let asset = AVURLAsset(url: videoURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-audio-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecipeImportError.fetchFailed("Não foi possível preparar extração de áudio.")
        }

        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a

        try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed:
                    continuation.resume(throwing: exporter.error ?? RecipeImportError.fetchFailed("Falha ao extrair áudio."))
                case .cancelled:
                    continuation.resume(throwing: RecipeImportError.cancelled)
                default:
                    continuation.resume(throwing: RecipeImportError.fetchFailed("Falha ao extrair áudio."))
                }
            }
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.intValue ?? 0
        RecipeImportLogger.debug("improver audio extracted bytes=\(fileSize)")
        return outputURL
    }

    private func transcribeAudio(fileURL: URL) async throws -> String {
        RecipeImportLogger.debug("improver transcribe audio with whisper-1")

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: fileURL)
        var body = Data()

        appendFormField(name: "model", value: "whisper-1", to: &body, boundary: boundary)
        appendFormField(name: "language", value: "pt", to: &body, boundary: boundary)
        appendFormField(name: "response_format", value: "text", to: &body, boundary: boundary)
        appendFileField(
            name: "file",
            filename: fileURL.lastPathComponent,
            mimeType: "audio/mp4",
            fileData: audioData,
            to: &body,
            boundary: boundary
        )

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RecipeImportError.aiFailed("Resposta inválida na transcrição de áudio.")
        }
        guard (200...299).contains(http.statusCode) else {
            let payload = String(data: data, encoding: .utf8) ?? ""
            throw RecipeImportError.aiFailed("Falha na transcrição (\(http.statusCode)): \(payload)")
        }

        let transcript = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard transcript.count >= 20 else {
            throw RecipeImportError.insufficientContent(suggestion: "A transcrição do vídeo retornou pouco conteúdo útil.")
        }
        return transcript
    }

    private func appendFormField(name: String, value: String, to body: inout Data, boundary: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    private func appendFileField(
        name: String,
        filename: String,
        mimeType: String,
        fileData: Data,
        to body: inout Data,
        boundary: String
    ) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
    }

    private func directVideoURL(from rawExternalURL: String) -> URL? {
        let trimmed = rawExternalURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        let ext = url.pathExtension.lowercased()
        let directExts = ["mp4", "mov", "m4v", "webm", "m3u8"]
        return directExts.contains(ext) ? url : nil
    }

    private func resolveVideoURL(from pageURL: URL) async throws -> URL? {
        RecipeImportLogger.debug("improver resolveVideoURL page=\(pageURL.absoluteString)")
        let host = pageURL.host?.lowercased() ?? ""

        if host.contains("instagram") {
            for embedURL in instagramEmbedCandidateURLs(for: pageURL) {
                RecipeImportLogger.debug("improver resolveVideoURL trying instagram embed=\(embedURL.absoluteString)")
                let embedHTML = try await fetchHTML(url: embedURL)
                if let url = extractFirstMatch(in: embedHTML, pattern: #"\\"video_url\\"\s*:\s*\\"([^"]+)\\""#) { return url }
                if let url = extractFirstMatch(in: embedHTML, pattern: #"\\"contentUrl\\"\s*:\s*\\"([^"]+\.mp4[^"]*)\\""#) { return url }
                if let url = extractFirstMatch(in: embedHTML, pattern: #"\\"shortcode_media\\".*?\\"video_url\\"\s*:\s*\\"([^"]+)\\""#) { return url }
                if let url = extractFirstMatch(in: embedHTML, pattern: #""video_url"\s*:\s*"([^"]+)""#) { return url }
                if let url = extractFirstMatch(in: embedHTML, pattern: #""contentUrl"\s*:\s*"([^"]+\.mp4[^"]*)""#) { return url }
                if let url = extractFirstMatch(in: embedHTML, pattern: #""shortcode_media".*?"video_url"\s*:\s*"([^"]+)""#) { return url }
            }
        }

        let html = try await fetchHTML(url: pageURL)

        if host.contains("tiktok") {
            if let url = extractFirstMatch(in: html, pattern: #""playAddr"\s*:\s*"([^"]+)""#) { return url }
            if let url = extractFirstMatch(in: html, pattern: #""downloadAddr"\s*:\s*"([^"]+)""#) { return url }
        }
        if host.contains("instagram") {
            if let url = extractFirstMatch(in: html, pattern: #"\\"video_url\\"\s*:\s*\\"([^"]+)\\""#) { return url }
            if let url = extractFirstMatch(in: html, pattern: #"\\"contentUrl\\"\s*:\s*\\"([^"]+\.mp4[^"]*)\\""#) { return url }
            if let url = extractFirstMatch(in: html, pattern: #""video_url"\s*:\s*"([^"]+)""#) { return url }
            if let url = extractFirstMatch(in: html, pattern: #""contentUrl"\s*:\s*"([^"]+\.mp4[^"]*)""#) { return url }
        }

        // Generic fallbacks across any page.
        if let url = extractFirstMatch(in: html, pattern: #"<meta[^>]+property=["']og:video(?::secure_url|:url)?["'][^>]+content=["']([^"']+)["']"#) { return url }
        if let url = extractFirstMatch(in: html, pattern: #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:video(?::secure_url|:url)?["']"#) { return url }
        if let url = extractFirstMatch(in: html, pattern: #"<video[^>]+src=["']([^"']+\.(?:mp4|m4v|webm|m3u8)[^"']*)["']"#) { return url }
        if let url = extractFirstMatch(in: html, pattern: #"<source[^>]+src=["']([^"']+\.(?:mp4|m4v|webm|m3u8)[^"']*)["']"#) { return url }

        RecipeImportLogger.debug("improver resolveVideoURL not found")
        return nil
    }

    private func instagramEmbedCandidateURLs(for pageURL: URL) -> [URL] {
        guard var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else {
            return []
        }

        let cleanPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleanPath.isEmpty else { return [] }

        components.query = nil
        components.fragment = nil

        var urls: [URL] = []
        components.path = "/\(cleanPath)/embed/captioned/"
        if let url = components.url { urls.append(url) }

        components.path = "/\(cleanPath)/embed/"
        if let url = components.url { urls.append(url) }

        return urls
    }

    private func extractFirstMatch(in html: String, pattern: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let ns = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }
        let raw = ns.substring(with: match.range(at: 1))
        let decoded = decodeEscapedString(raw)
        guard let url = URL(string: decoded), url.scheme?.hasPrefix("http") == true else { return nil }
        RecipeImportLogger.debug("improver resolveVideoURL match=\(url.absoluteString)")
        return url
    }

    private func decodeEscapedString(_ input: String) -> String {
        var decoded = input

        for _ in 0..<4 {
            let quoted = "\"\(decoded.replacingOccurrences(of: "\"", with: "\\\""))\""
            guard let data = quoted.data(using: .utf8),
                  let unescaped = try? JSONDecoder().decode(String.self, from: data),
                  unescaped != decoded else {
                break
            }
            decoded = unescaped
        }

        decoded = decoded.replacingOccurrences(of: #"\u0026"#, with: "&")
        decoded = decoded.replacingOccurrences(of: #"\u002F"#, with: "/")
        decoded = decoded.replacingOccurrences(of: #"\u003D"#, with: "=")
        decoded = decoded.replacingOccurrences(of: #"\u0025"#, with: "%")
        decoded = decoded.replacingOccurrences(of: "\\\\/", with: "\\/")
        decoded = decoded.replacingOccurrences(of: "\\/", with: "/")
        decoded = decoded.replacingOccurrences(of: "&amp;", with: "&")
        return decoded
    }

    private func fetchHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("pt-BR,pt;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RecipeImportError.fetchFailed("Não foi possível carregar a página do vídeo.")
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private func mergeDuplicateIngredients(_ ingredients: [IngredientDraft]) -> [IngredientDraft] {
        var merged: [String: IngredientDraft] = [:]

        for ingredient in ingredients {
            let key = [ingredient.name, ingredient.unit, ingredient.preparationState]
                .map { RecipeOptionCatalog.normalized($0) }
                .joined(separator: "|")

            if var existing = merged[key] {
                if let quantity = ingredient.quantity {
                    existing.quantity = (existing.quantity ?? 0) + quantity
                }
                existing.confidence = max(existing.confidence, ingredient.confidence)
                if existing.iconName == nil {
                    existing.iconName = ingredient.iconName
                }
                merged[key] = existing
            } else {
                merged[key] = ingredient
            }
        }

        return merged.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
