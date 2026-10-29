import Foundation
#if DEBUG && os(iOS)
import Security

enum DebugOpenRouterCredential {
    private static let service = "com.pedrosalles.smartkitchen.sync.debug.openrouter"
    private static let account = "api-key"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    static func read() -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ rawKey: String) throws {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-or-"), key.count >= 20,
              !key.contains(where: \.isWhitespace) else { throw CredentialError.invalidKey }
        let values = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query.merging(values) { _, new in new }
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(insertion as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CredentialError.keychain(status) }
    }

    enum CredentialError: LocalizedError {
        case invalidKey
        case keychain(OSStatus)
        var errorDescription: String? {
            switch self {
            case .invalidKey:
                String(localized: "Insira uma chave OpenRouter válida, começando com sk-or-.")
            case .keychain(let status):
                String(format: String(localized: "Não foi possível salvar a chave (%@)."), String(status))
            }
        }
    }
}
#endif

enum APIConfig {
    static var openAIAPIKey: String {
        debugProviderValue(infoKey: "OpenAIAPIKey", envKey: "OPENAI_API_KEY")
    }

    static var openRouterAPIKey: String {
        #if DEBUG && os(iOS)
        if let local = DebugOpenRouterCredential.read(), !local.isEmpty { return local }
        #endif
        return debugProviderValue(infoKey: "OpenRouterAPIKey", envKey: "OPENROUTER_API_KEY")
    }

    static var usesLocalOpenRouter: Bool {
        #if DEBUG && os(iOS)
        // A configured server owns provider selection and secrets, including fallback.
        // A local debug key must never bypass that server.
        return !hasSupabaseCredentials && !(DebugOpenRouterCredential.read() ?? "").isEmpty
        #else
        return false
        #endif
    }

    static var missingAIConfigurationMessage: String {
        #if DEBUG && os(iOS)
        String(localized: "Nenhum provedor de IA está disponível. Configure o OpenRouter em Configurações > Central de Debug > IA.")
        #else
        String(localized: "O serviço de IA está indisponível. Tente novamente ou contate o suporte.")
        #endif
    }

    static var exaAPIKey: String {
        debugProviderValue(infoKey: "ExaAPIKey", envKey: "EXA_API_KEY")
    }

    static var supabaseURL: String {
        bundleValue(infoKey: "SupabaseURL", envKey: "SUPABASE_URL")
    }

    static var supabaseAnonKey: String {
        bundleValue(infoKey: "SupabaseAnonKey", envKey: "SUPABASE_ANON_KEY")
    }

    static var hasSupabaseCredentials: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }

    static var hasAIBackend: Bool {
        hasSupabaseCredentials || !openAIAPIKey.isEmpty || !openRouterAPIKey.isEmpty
    }

    static var hasExaBackend: Bool {
        hasSupabaseCredentials || !exaAPIKey.isEmpty
    }

    private static func bundleValue(infoKey: String, envKey: String) -> String {
        if let rawValue = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.hasPrefix("$(") {
                return trimmed
            }
        }

#if DEBUG
        return ProcessInfo.processInfo.environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
#endif

        return ""
    }

    private static func debugProviderValue(infoKey: String, envKey: String) -> String {
#if DEBUG
        return bundleValue(infoKey: infoKey, envKey: envKey)
#else
        return ""
#endif
    }
}


#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Consent is local to this installation; it is never inferred from iCloud,
/// onboarding completion, a subscription, or permission to use the camera.
@MainActor
final class AIDataConsent {
    static let shared = AIDataConsent()
    static let preferenceKey = "Savoria.aiDataConsent.v1"
    private let defaults: UserDefaults
    private let prompt: @MainActor () async -> Bool?
    private var pending: Task<Bool?, Never>?
    private var generation = 0

    init(defaults: UserDefaults = .standard,
         prompt: @escaping @MainActor () async -> Bool? = { await AIDataConsent.presentPermission() }) {
        self.defaults = defaults
        self.prompt = prompt
    }

    var isGranted: Bool { defaults.integer(forKey: Self.preferenceKey) == 1 }

    func requireGranted() throws {
        try Task.checkCancellation()
        guard isGranted else { throw CancellationError() }
    }

    func revoke() {
        generation += 1
        defaults.set(-1, forKey: Self.preferenceKey)
    }

    func requestAgain() async throws {
        if !isGranted { defaults.removeObject(forKey: Self.preferenceKey) }
        try await request()
    }

    func request() async throws {
        try Task.checkCancellation()
        if isGranted { return }
        guard defaults.integer(forKey: Self.preferenceKey) != -1 else { throw CancellationError() }
        let revision = generation
        let task: Task<Bool?, Never>
        if let pending { task = pending }
        else {
            task = Task { await prompt() }
            pending = task
        }
        let decision = await task.value
        pending = nil
        guard let accepted = decision else { throw CancellationError() }
        guard revision == generation else { throw CancellationError() }
        defaults.set(accepted ? 1 : -1, forKey: Self.preferenceKey)
        // A cancelled operation never sends its payload, even if permission was granted.
        try requireGranted()
    }

    private static func presentPermission() async -> Bool? {
        let title = String(localized: "Permitir serviços de IA?")
        let message = String(localized: "Para atender seus pedidos, o Savoria envia mensagens, ingredientes, dados nutricionais e as fotos ou áudios escolhidos aos serviços externos necessários: Supabase, OpenAI, OpenRouter e seus provedores de modelos, e Exa para buscas. O contexto pode incluir itens da despensa e informações do seu perfil nutricional. Autorize somente se concordar com esse envio. Você pode revogar a autorização em Configurações e continuar usando os recursos locais. Consulte a Política de privacidade em Configurações.")
        let allow = String(localized: "Permitir")
        let deny = String(localized: "Agora não")
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
        while let presented = presenter.presentedViewController { presenter = presented }
        guard presenter.viewIfLoaded?.window != nil, !presenter.isBeingDismissed else { return nil }
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: deny, style: .cancel) { _ in continuation.resume(returning: false) })
            alert.addAction(UIAlertAction(title: allow, style: .default) { _ in continuation.resume(returning: true) })
            presenter.present(alert, animated: true)
        }
        #elseif os(macOS)
        guard NSApp.isActive, let window = NSApp.keyWindow, window.attachedSheet == nil else { return nil }
        return await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: allow)
            alert.addButton(withTitle: deny)
            alert.buttons.last?.keyEquivalent = "\u{1b}"
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .alertFirstButtonReturn)
            }
        }
        #else
        return nil
        #endif
    }
}
