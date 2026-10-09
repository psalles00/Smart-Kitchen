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
        return !(DebugOpenRouterCredential.read() ?? "").isEmpty
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
