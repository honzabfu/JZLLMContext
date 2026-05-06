import Carbon
import Foundation

enum TokenParamStyle: String, Codable, CaseIterable {
    case maxCompletionTokens
    case maxTokens
    case maxOutputTokens
    case maxNewTokens

    var parameterName: String {
        switch self {
        case .maxCompletionTokens: "max_completion_tokens"
        case .maxTokens:           "max_tokens"
        case .maxOutputTokens:     "max_output_tokens"
        case .maxNewTokens:        "max_new_tokens"
        }
    }

    var displayName: String {
        switch self {
        case .maxCompletionTokens: L("token_param.max_completion")
        case .maxTokens:           L("token_param.max_tokens")
        case .maxOutputTokens:     L("token_param.max_output")
        case .maxNewTokens:        L("token_param.max_new")
        }
    }
}

enum AppLanguage: String, Codable, CaseIterable {
    case system
    case cs
    case en
    case es

    var displayName: String {
        switch self {
        case .system: "Systémový"
        case .cs:     "Čeština"
        case .en:     "English"
        case .es:     "Español"
        }
    }

    var resolvedLocale: Locale {
        switch self {
        case .system:
            let code = Locale.current.language.languageCode?.identifier ?? "en"
            switch code {
            case "cs": return Locale(identifier: "cs")
            case "es": return Locale(identifier: "es")
            default:   return Locale(identifier: "en")
            }
        case .cs: return Locale(identifier: "cs")
        case .en: return Locale(identifier: "en")
        case .es: return Locale(identifier: "es")
        }
    }
}

struct ModelPreset: Identifiable, Codable, Equatable {
    let id: String
    var displayName: String
    var isRecommended: Bool

    init(id: String, displayName: String, isRecommended: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.isRecommended = isRecommended
    }
}

// MARK: - CustomProvider

struct CustomProvider: Codable, Identifiable {
    var id: UUID
    var name: String
    var baseURL: String
    var apiVersion: String?
    var tokenParamStyle: TokenParamStyle
    var requiresAPIKey: Bool
    var customHeaders: [String: String]

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        apiVersion: String? = nil,
        tokenParamStyle: TokenParamStyle = .maxTokens,
        requiresAPIKey: Bool = false,
        customHeaders: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiVersion = apiVersion
        self.tokenParamStyle = tokenParamStyle
        self.requiresAPIKey = requiresAPIKey
        self.customHeaders = customHeaders
    }
}

// MARK: - ProviderType

struct ProviderType: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    let rawValue: String
    var id: String { rawValue }

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    static let openai       = ProviderType("openai")
    static let azureOpenai  = ProviderType("azure_openai")
    static let azureOpenai2 = ProviderType("azure_openai_2")
    static let anthropic    = ProviderType("anthropic")
    static let gemini       = ProviderType("gemini")
    static let grok         = ProviderType("grok")

    static let builtIn: [ProviderType] = [.openai, .azureOpenai, .azureOpenai2, .anthropic, .gemini, .grok]

    static var allCases: [ProviderType] {
        builtIn + ConfigStore.shared.config.customProviders
            .map { ProviderType($0.id.uuidString) }
    }

    var isCustom: Bool { !Self.builtIn.contains(self) }

    var customProvider: CustomProvider? {
        ConfigStore.shared.config.customProviders.first { $0.id.uuidString == rawValue }
    }

    var requiresApiKey: Bool {
        isCustom ? (customProvider?.requiresAPIKey ?? false) : true
    }
}

// MARK: - AppConfig

struct AppConfig: Codable {
    var schemaVersion: Int
    var hotkeyKeyCode: Int
    var hotkeyModifiers: Int
    var actions: [Action]
    // Azure AI – slot 1
    var azureEndpoint: String?
    var azureDeploymentName: String?
    var azureAPIVersion: String?
    // Azure AI – slot 2
    var azureEndpoint2: String?
    var azureDeploymentName2: String?
    var azureAPIVersion2: String?
    // Dynamic custom OpenAI-compatible providers
    var customProviders: [CustomProvider]
    var autoCopyAndClose: Bool
    var historyLimit: Int
    var markdownOutput: Bool
    var modelPresets: [String: [ModelPreset]]
    var autoUpdateCheck: Bool
    var appLanguage: AppLanguage
    var historyLogEnabled: Bool
    var historyLogDirectory: String?
    var historyLogWarningShown: Bool
    var historyLogFilePrefix: String
    var sensitiveContentCheckEnabled: Bool
    var customSensitivePatterns: [SensitivePattern]
    // Global model filters
    var modelExcludeFilters: [String]
    var modelIncludeFilters: [String]

    static let defaultAzureAPIVersion = "2024-10-21"

    init(
        schemaVersion: Int,
        hotkeyKeyCode: Int,
        hotkeyModifiers: Int,
        actions: [Action],
        azureEndpoint: String? = nil,
        azureDeploymentName: String? = nil,
        azureAPIVersion: String? = nil,
        azureEndpoint2: String? = nil,
        azureDeploymentName2: String? = nil,
        azureAPIVersion2: String? = nil,
        customProviders: [CustomProvider] = [],
        autoCopyAndClose: Bool = false,
        historyLimit: Int = 5,
        markdownOutput: Bool = true,
        modelPresets: [String: [ModelPreset]] = [:],
        autoUpdateCheck: Bool = true,
        appLanguage: AppLanguage = .system,
        historyLogEnabled: Bool = false,
        historyLogDirectory: String? = nil,
        historyLogWarningShown: Bool = false,
        historyLogFilePrefix: String = "",
        sensitiveContentCheckEnabled: Bool = true,
        customSensitivePatterns: [SensitivePattern] = [],
        modelExcludeFilters: [String] = [],
        modelIncludeFilters: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.actions = actions
        self.azureEndpoint = azureEndpoint
        self.azureDeploymentName = azureDeploymentName
        self.azureAPIVersion = azureAPIVersion
        self.azureEndpoint2 = azureEndpoint2
        self.azureDeploymentName2 = azureDeploymentName2
        self.azureAPIVersion2 = azureAPIVersion2
        self.customProviders = customProviders
        self.autoCopyAndClose = autoCopyAndClose
        self.historyLimit = historyLimit
        self.markdownOutput = markdownOutput
        self.modelPresets = modelPresets
        self.autoUpdateCheck = autoUpdateCheck
        self.appLanguage = appLanguage
        self.historyLogEnabled = historyLogEnabled
        self.historyLogDirectory = historyLogDirectory
        self.historyLogWarningShown = historyLogWarningShown
        self.historyLogFilePrefix = historyLogFilePrefix
        self.sensitiveContentCheckEnabled = sensitiveContentCheckEnabled
        self.customSensitivePatterns = customSensitivePatterns
        self.modelExcludeFilters = modelExcludeFilters
        self.modelIncludeFilters = modelIncludeFilters
    }

    // Legacy decode-only keys (schemaVersion < 2)
    private enum LegacyCodingKeys: String, CodingKey {
        case customOpenAIBaseURL, customOpenAIAPIVersion, customOpenAITokenParam
        case customOpenAIBaseURL2, customOpenAIAPIVersion2, customOpenAITokenParam2
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion        = try c.decode(Int.self, forKey: .schemaVersion)
        hotkeyKeyCode        = try c.decode(Int.self, forKey: .hotkeyKeyCode)
        hotkeyModifiers      = try c.decode(Int.self, forKey: .hotkeyModifiers)
        actions              = try c.decode([Action].self, forKey: .actions)
        azureEndpoint        = try c.decodeIfPresent(String.self, forKey: .azureEndpoint)
        azureDeploymentName  = try c.decodeIfPresent(String.self, forKey: .azureDeploymentName)
        azureAPIVersion      = try c.decodeIfPresent(String.self, forKey: .azureAPIVersion)
        azureEndpoint2       = try c.decodeIfPresent(String.self, forKey: .azureEndpoint2)
        azureDeploymentName2 = try c.decodeIfPresent(String.self, forKey: .azureDeploymentName2)
        azureAPIVersion2     = try c.decodeIfPresent(String.self, forKey: .azureAPIVersion2)
        customProviders      = try c.decodeIfPresent([CustomProvider].self, forKey: .customProviders) ?? []
        autoCopyAndClose     = try c.decodeIfPresent(Bool.self, forKey: .autoCopyAndClose) ?? false
        historyLimit         = try c.decodeIfPresent(Int.self, forKey: .historyLimit) ?? 5
        markdownOutput       = try c.decodeIfPresent(Bool.self, forKey: .markdownOutput) ?? true
        modelPresets         = try c.decodeIfPresent([String: [ModelPreset]].self, forKey: .modelPresets) ?? [:]
        autoUpdateCheck      = try c.decodeIfPresent(Bool.self, forKey: .autoUpdateCheck) ?? true
        appLanguage          = try c.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .system
        historyLogEnabled    = try c.decodeIfPresent(Bool.self, forKey: .historyLogEnabled) ?? false
        historyLogDirectory  = try c.decodeIfPresent(String.self, forKey: .historyLogDirectory)
        historyLogWarningShown = try c.decodeIfPresent(Bool.self, forKey: .historyLogWarningShown) ?? false
        historyLogFilePrefix = try c.decodeIfPresent(String.self, forKey: .historyLogFilePrefix) ?? ""
        sensitiveContentCheckEnabled = try c.decodeIfPresent(Bool.self, forKey: .sensitiveContentCheckEnabled) ?? true
        customSensitivePatterns = try c.decodeIfPresent([SensitivePattern].self, forKey: .customSensitivePatterns) ?? []
        modelExcludeFilters  = try c.decodeIfPresent([String].self, forKey: .modelExcludeFilters) ?? []
        modelIncludeFilters  = try c.decodeIfPresent([String].self, forKey: .modelIncludeFilters) ?? []

        // Migrate schemaVersion 1 → 2: convert flat custom OpenAI fields to CustomProvider list
        if schemaVersion < 2 {
            let lc = try decoder.container(keyedBy: LegacyCodingKeys.self)
            let url1   = try lc.decodeIfPresent(String.self, forKey: .customOpenAIBaseURL)
            let ver1   = try lc.decodeIfPresent(String.self, forKey: .customOpenAIAPIVersion)
            let tok1   = try lc.decodeIfPresent(TokenParamStyle.self, forKey: .customOpenAITokenParam) ?? .maxTokens
            let url2   = try lc.decodeIfPresent(String.self, forKey: .customOpenAIBaseURL2)
            let ver2   = try lc.decodeIfPresent(String.self, forKey: .customOpenAIAPIVersion2)
            let tok2   = try lc.decodeIfPresent(TokenParamStyle.self, forKey: .customOpenAITokenParam2) ?? .maxTokens

            var migrated: [CustomProvider] = customProviders
            var oldToNew: [String: String] = [:]  // old rawValue → new UUID string

            if let url = url1, !url.isEmpty {
                let cp = CustomProvider(name: L("provider.custom1"), baseURL: url,
                                        apiVersion: ver1, tokenParamStyle: tok1)
                migrated.append(cp)
                oldToNew["custom_openai"] = cp.id.uuidString
                // Copy Keychain entry to new UUID-based key
                if let key = KeychainStore.loadRaw(account: "jzllmcontext.custom_openai.apikey") {
                    KeychainStore.saveRaw(key, account: "jzllmcontext.\(cp.id.uuidString).apikey")
                }
            }
            if let url = url2, !url.isEmpty {
                let cp = CustomProvider(name: L("provider.custom2"), baseURL: url,
                                        apiVersion: ver2, tokenParamStyle: tok2)
                migrated.append(cp)
                oldToNew["custom_openai_2"] = cp.id.uuidString
                if let key = KeychainStore.loadRaw(account: "jzllmcontext.custom_openai_2.apikey") {
                    KeychainStore.saveRaw(key, account: "jzllmcontext.\(cp.id.uuidString).apikey")
                }
            }

            // Update action provider references and modelPresets keys
            if !oldToNew.isEmpty {
                actions = actions.map { action in
                    var a = action
                    if let newID = oldToNew[action.provider.rawValue] {
                        a.provider = ProviderType(newID)
                    }
                    return a
                }
                for (oldKey, newKey) in oldToNew where modelPresets[oldKey] != nil {
                    modelPresets[newKey] = modelPresets.removeValue(forKey: oldKey)
                }
            }
            customProviders = migrated
            schemaVersion = 2
        }
    }

    static var `default`: AppConfig { makeDefault() }

    static func makeDefault(language: AppLanguage = .system) -> AppConfig {
        let code: String
        switch language {
        case .system:
            let sys = Locale.current.language.languageCode?.identifier ?? "en"
            code = ["cs", "es"].contains(sys) ? sys : "en"
        case .cs: code = "cs"
        case .en: code = "en"
        case .es: code = "es"
        }
        return AppConfig(
            schemaVersion: 2,
            hotkeyKeyCode: Int(kVK_Space),
            hotkeyModifiers: Int(cmdKey | shiftKey),
            actions: defaultActions(forLang: code),
            appLanguage: language
        )
    }

    private static func defaultActions(forLang lang: String) -> [Action] {
        switch lang {
        case "es":
            return [
                Action(
                    name: "Traducir al español",
                    systemPrompt: "Traduce el siguiente texto al español. Responde solo con la traducción.",
                    provider: .anthropic, model: "claude-sonnet-4-6", enabled: true, temperature: 0.1
                ),
                Action(
                    name: "Reescribir + gramática",
                    systemPrompt: "Reescribe el siguiente texto para que sea más claro y gramaticalmente correcto. Mantén el idioma original. Responde solo con el texto reescrito. No añadas información adicional.",
                    provider: .openai, model: "gpt-5.4-mini", enabled: true, temperature: 0.2
                ),
                Action(
                    name: "Simplificar y explicar",
                    systemPrompt: "Explica el siguiente texto de forma sencilla para un profesional ocupado.\nSé conciso y céntrate en la comprensión práctica.",
                    provider: .openai, model: "gpt-5.4-mini", enabled: true, temperature: 0.5
                ),
                Action(
                    name: "Resumir en puntos",
                    systemPrompt: "Resume el siguiente texto en:\n- 3 puntos principales\n- 1 frase resumen corta\n- entidades clave (si las hay)\nNo añadas información adicional.",
                    provider: .openai, model: "gpt-5.4-mini", enabled: true, temperature: 0.2
                ),
                Action(
                    name: "Preparar respuesta",
                    systemPrompt: "Escribe una respuesta breve y profesional al siguiente mensaje.\nEstilo: neutral, cortés\nLongitud: corta",
                    provider: .openai, model: "gpt-5.5", enabled: true, temperature: 0.5
                )
            ]
        case "en":
            return [
                Action(
                    name: "Translate to English",
                    systemPrompt: "Translate the following text to English. Reply with the translation only.",
                    provider: .anthropic, model: "claude-sonnet-4-6", enabled: true, temperature: 0.1
                ),
                Action(
                    name: "Rewrite + Grammar",
                    systemPrompt: "Rewrite the following text to be clearer and grammatically correct. Keep the original language. Reply with the rewritten text only. Do not add any extra information.",
                    provider: .openai, model: "gpt-5.4-mini", enabled: true, temperature: 0.2
                ),
                Action(
                    name: "Simplify & Explain",
                    systemPrompt: "Explain the following text simply for a busy professional.\nBe concise and focus on practical understanding.",
                    provider: .openai, model: "gpt-5.4-mini", enabled: true, temperature: 0.5
                ),
                Action(
                    name: "Summarize to Bullets",
                    systemPrompt: "Summarize the following text into:\n- 3 main points\n- 1 short summary sentence\n- key entities (if any)\nDo not add any extra information.",
                    provider: .openai, model: "gpt-5.4-mini", enabled: true, temperature: 0.2
                ),
                Action(
                    name: "Draft a Reply",
                    systemPrompt: "Write a brief and professional reply to the following message.\nStyle: neutral, polite\nLength: short",
                    provider: .openai, model: "gpt-5.5", enabled: true, temperature: 0.5
                )
            ]
        default: // cs
            return [
                Action(
                    name: "Přeložit do češtiny",
                    systemPrompt: "Přelož následující text do češtiny. Odpověz pouze překladem.",
                    provider: .anthropic, model: "claude-sonnet-4-6", enabled: true, temperature: 0.1
                ),
                Action(
                    name: "Přepsat + gramatika",
                    systemPrompt: "Přepiš následující text tak, aby byl srozumitelnější a gramaticky správný. Zachovej původní jazyk. Odpověz pouze přepsaným textem. Nepřidávej žádné další informace navíc.",
                    provider: .openai, model: "gpt-5.4-mini", enabled: true, temperature: 0.2
                ),
                Action(
                    name: "Zjednoduš a vysvětli",
                    systemPrompt: "Vysvětli následující text jednoduše pro zaneprázdněného profesionála.\nBuď stručný a zaměř se na praktické pochopení.",
                    provider: .openai, model: "gpt-5.4-mini", enabled: true, temperature: 0.5
                ),
                Action(
                    name: "Shrň do odrážek",
                    systemPrompt: "Shrň následující text do:\n- 3 hlavních bodů\n- 1 krátké shrnující věty\n- důležitých entit (pokud existují)\nNepřidávej žádné další informace navíc.",
                    provider: .openai, model: "gpt-5.4-mini", enabled: true, temperature: 0.2
                ),
                Action(
                    name: "Připrav odpověď",
                    systemPrompt: "Napiš stručnou a profesionální odpověď na následující zprávu.\nStyl: neutrální, zdvořilý\nDélka: krátká",
                    provider: .openai, model: "gpt-5.5",
                    enabled: true,
                    temperature: 0.5
                )
            ]
        }
    }
}

struct Action: Codable, Identifiable, Hashable, Equatable {
    var id: UUID
    var name: String
    var systemPrompt: String
    var provider: ProviderType
    var model: String
    var enabled: Bool
    var temperature: Double
    var maxTokens: Int
    var autoCopyClose: AutoCopyClose
    var isDefault: Bool

    init(
        name: String,
        systemPrompt: String,
        provider: ProviderType,
        model: String,
        enabled: Bool,
        temperature: Double = 0.7,
        maxTokens: Int = 2048,
        autoCopyClose: AutoCopyClose = .useGlobal,
        isDefault: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.systemPrompt = systemPrompt
        self.provider = provider
        self.model = model
        self.enabled = enabled
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.autoCopyClose = autoCopyClose
        self.isDefault = isDefault
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self, forKey: .id)
        name          = try c.decode(String.self, forKey: .name)
        systemPrompt  = try c.decode(String.self, forKey: .systemPrompt)
        provider      = try c.decode(ProviderType.self, forKey: .provider)
        model         = try c.decode(String.self, forKey: .model)
        enabled       = try c.decode(Bool.self, forKey: .enabled)
        temperature   = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.7
        maxTokens     = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 2048
        autoCopyClose = try c.decodeIfPresent(AutoCopyClose.self, forKey: .autoCopyClose) ?? .useGlobal
        isDefault     = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }
}

// MARK: - ProviderType model helpers

extension ProviderType {
    func effectiveModels() -> [ModelPreset] {
        let cfg = ConfigStore.shared.config
        let stored = cfg.modelPresets[rawValue] ?? []
        var result = stored.isEmpty ? presetModels : stored
        if !cfg.modelIncludeFilters.isEmpty {
            result = result.filter { p in
                cfg.modelIncludeFilters.contains { p.id.lowercased().contains($0.lowercased()) }
            }
        }
        if !cfg.modelExcludeFilters.isEmpty {
            result = result.filter { p in
                !cfg.modelExcludeFilters.contains { p.id.lowercased().contains($0.lowercased()) }
            }
        }
        return result
    }

    var presetModels: [ModelPreset] {
        if self == .openai {
            return [
                .init(id: "gpt-5.5",      displayName: "gpt-5.5",             isRecommended: true),
                .init(id: "gpt-5.4-mini", displayName: "gpt-5.4-mini"),
                .init(id: "o4-mini",      displayName: "o4-mini (legacy)"),
                .init(id: "o3",           displayName: "o3 (legacy)"),
                .init(id: "o3-mini",      displayName: "o3-mini (legacy)"),
                .init(id: "gpt-4o",       displayName: "gpt-4o (legacy)"),
                .init(id: "gpt-4o-mini",  displayName: "gpt-4o-mini (legacy)")
            ]
        }
        if self == .anthropic {
            return [
                .init(id: "claude-sonnet-4-6",        displayName: "claude-sonnet-4.6", isRecommended: true),
                .init(id: "claude-opus-4-7",           displayName: "claude-opus-4.7"),
                .init(id: "claude-haiku-4-5-20251001", displayName: "claude-haiku-4.5")
            ]
        }
        if self == .gemini {
            return [
                .init(id: "gemini-3.1-pro",         displayName: "gemini-3.1-pro",         isRecommended: true),
                .init(id: "gemini-3-flash-preview",  displayName: "gemini-3-flash-preview"),
                .init(id: "gemini-3.1-flash-lite",   displayName: "gemini-3.1-flash-lite")
            ]
        }
        if self == .grok {
            return [
                .init(id: "grok-4.20",               displayName: "grok-4.20",               isRecommended: true),
                .init(id: "grok-4.20-non-reasoning",  displayName: "grok-4.20-non-reasoning"),
                .init(id: "grok-4-1-fast-reasoning",  displayName: "grok-4.1-fast-reasoning")
            ]
        }
        // azureOpenai, azureOpenai2, custom providers
        return []
    }
}

enum AutoCopyClose: String, Codable, CaseIterable {
    case useGlobal
    case always
    case never

    var displayName: String {
        switch self {
        case .useGlobal: L("autocopy.use_global")
        case .always:    L("autocopy.always")
        case .never:     L("autocopy.never")
        }
    }
}
