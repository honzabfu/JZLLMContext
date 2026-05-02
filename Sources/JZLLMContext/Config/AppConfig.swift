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
    var customOpenAIBaseURL: String?
    var customOpenAIAPIVersion: String?
    var customOpenAITokenParam: TokenParamStyle = .maxTokens
    var customOpenAIBaseURL2: String?
    var customOpenAIAPIVersion2: String?
    var customOpenAITokenParam2: TokenParamStyle = .maxTokens
    var autoCopyAndClose: Bool = false
    var historyLimit: Int = 5
    var markdownOutput: Bool = true
    var modelPresets: [String: [ModelPreset]] = [:]
    var autoUpdateCheck: Bool = true
    var appLanguage: AppLanguage = .system
    var historyLogEnabled: Bool = false
    var historyLogDirectory: String? = nil
    var historyLogWarningShown: Bool = false
    var historyLogFilePrefix: String = ""
    var sensitiveContentCheckEnabled: Bool = true
    var customSensitivePatterns: [SensitivePattern] = []

    static let defaultAzureAPIVersion = "2024-10-21"

    init(schemaVersion: Int, hotkeyKeyCode: Int, hotkeyModifiers: Int, actions: [Action],
         azureEndpoint: String? = nil, azureDeploymentName: String? = nil, azureAPIVersion: String? = nil,
         azureEndpoint2: String? = nil, azureDeploymentName2: String? = nil, azureAPIVersion2: String? = nil,
         customOpenAIBaseURL: String? = nil, customOpenAIAPIVersion: String? = nil, customOpenAITokenParam: TokenParamStyle = .maxTokens,
         customOpenAIBaseURL2: String? = nil, customOpenAIAPIVersion2: String? = nil, customOpenAITokenParam2: TokenParamStyle = .maxTokens,
         autoCopyAndClose: Bool = false, historyLimit: Int = 5, markdownOutput: Bool = true,
         modelPresets: [String: [ModelPreset]] = [:],
         autoUpdateCheck: Bool = true,
         appLanguage: AppLanguage = .system,
         historyLogEnabled: Bool = false,
         historyLogDirectory: String? = nil,
         historyLogWarningShown: Bool = false,
         historyLogFilePrefix: String = "",
         sensitiveContentCheckEnabled: Bool = true,
         customSensitivePatterns: [SensitivePattern] = []) {
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
        self.customOpenAIBaseURL = customOpenAIBaseURL
        self.customOpenAIAPIVersion = customOpenAIAPIVersion
        self.customOpenAITokenParam = customOpenAITokenParam
        self.customOpenAIBaseURL2 = customOpenAIBaseURL2
        self.customOpenAIAPIVersion2 = customOpenAIAPIVersion2
        self.customOpenAITokenParam2 = customOpenAITokenParam2
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
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        hotkeyKeyCode = try c.decode(Int.self, forKey: .hotkeyKeyCode)
        hotkeyModifiers = try c.decode(Int.self, forKey: .hotkeyModifiers)
        actions = try c.decode([Action].self, forKey: .actions)
        azureEndpoint = try c.decodeIfPresent(String.self, forKey: .azureEndpoint)
        azureDeploymentName = try c.decodeIfPresent(String.self, forKey: .azureDeploymentName)
        azureAPIVersion = try c.decodeIfPresent(String.self, forKey: .azureAPIVersion)
        azureEndpoint2 = try c.decodeIfPresent(String.self, forKey: .azureEndpoint2)
        azureDeploymentName2 = try c.decodeIfPresent(String.self, forKey: .azureDeploymentName2)
        azureAPIVersion2 = try c.decodeIfPresent(String.self, forKey: .azureAPIVersion2)
        customOpenAIBaseURL = try c.decodeIfPresent(String.self, forKey: .customOpenAIBaseURL)
        customOpenAIAPIVersion = try c.decodeIfPresent(String.self, forKey: .customOpenAIAPIVersion)
        customOpenAITokenParam = try c.decodeIfPresent(TokenParamStyle.self, forKey: .customOpenAITokenParam) ?? .maxTokens
        customOpenAIBaseURL2 = try c.decodeIfPresent(String.self, forKey: .customOpenAIBaseURL2)
        customOpenAIAPIVersion2 = try c.decodeIfPresent(String.self, forKey: .customOpenAIAPIVersion2)
        customOpenAITokenParam2 = try c.decodeIfPresent(TokenParamStyle.self, forKey: .customOpenAITokenParam2) ?? .maxTokens
        autoCopyAndClose = try c.decodeIfPresent(Bool.self, forKey: .autoCopyAndClose) ?? false
        historyLimit = try c.decodeIfPresent(Int.self, forKey: .historyLimit) ?? 5
        markdownOutput = try c.decodeIfPresent(Bool.self, forKey: .markdownOutput) ?? true
        modelPresets = try c.decodeIfPresent([String: [ModelPreset]].self, forKey: .modelPresets) ?? [:]
        autoUpdateCheck = try c.decodeIfPresent(Bool.self, forKey: .autoUpdateCheck) ?? true
        appLanguage = try c.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .system
        historyLogEnabled = try c.decodeIfPresent(Bool.self, forKey: .historyLogEnabled) ?? false
        historyLogDirectory = try c.decodeIfPresent(String.self, forKey: .historyLogDirectory)
        historyLogWarningShown = try c.decodeIfPresent(Bool.self, forKey: .historyLogWarningShown) ?? false
        historyLogFilePrefix = try c.decodeIfPresent(String.self, forKey: .historyLogFilePrefix) ?? ""
        sensitiveContentCheckEnabled = try c.decodeIfPresent(Bool.self, forKey: .sensitiveContentCheckEnabled) ?? true
        customSensitivePatterns = try c.decodeIfPresent([SensitivePattern].self, forKey: .customSensitivePatterns) ?? []
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
            schemaVersion: 1,
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
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        systemPrompt = try c.decode(String.self, forKey: .systemPrompt)
        provider = try c.decode(ProviderType.self, forKey: .provider)
        model = try c.decode(String.self, forKey: .model)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.7
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 2048
        autoCopyClose = try c.decodeIfPresent(AutoCopyClose.self, forKey: .autoCopyClose) ?? .useGlobal
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
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

enum ProviderType: String, Codable, CaseIterable {
    case openai
    case azureOpenai = "azure_openai"
    case azureOpenai2 = "azure_openai_2"
    case anthropic
    case gemini
    case grok
    case customOpenAI = "custom_openai"
    case customOpenAI2 = "custom_openai_2"
}
