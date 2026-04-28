import Carbon
import Foundation

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
    var customOpenAIBaseURL2: String?
    var customOpenAIAPIVersion2: String?
    var autoCopyAndClose: Bool = false
    var historyLimit: Int = 5
    var modelPresets: [String: [ModelPreset]] = [:]

    static let defaultAzureAPIVersion = "2024-10-21"

    init(schemaVersion: Int, hotkeyKeyCode: Int, hotkeyModifiers: Int, actions: [Action],
         azureEndpoint: String? = nil, azureDeploymentName: String? = nil, azureAPIVersion: String? = nil,
         azureEndpoint2: String? = nil, azureDeploymentName2: String? = nil, azureAPIVersion2: String? = nil,
         customOpenAIBaseURL: String? = nil, customOpenAIAPIVersion: String? = nil,
         customOpenAIBaseURL2: String? = nil, customOpenAIAPIVersion2: String? = nil,
         autoCopyAndClose: Bool = false, historyLimit: Int = 5,
         modelPresets: [String: [ModelPreset]] = [:]) {
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
        self.customOpenAIBaseURL2 = customOpenAIBaseURL2
        self.customOpenAIAPIVersion2 = customOpenAIAPIVersion2
        self.autoCopyAndClose = autoCopyAndClose
        self.historyLimit = historyLimit
        self.modelPresets = modelPresets
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
        customOpenAIBaseURL2 = try c.decodeIfPresent(String.self, forKey: .customOpenAIBaseURL2)
        customOpenAIAPIVersion2 = try c.decodeIfPresent(String.self, forKey: .customOpenAIAPIVersion2)
        autoCopyAndClose = try c.decodeIfPresent(Bool.self, forKey: .autoCopyAndClose) ?? false
        historyLimit = try c.decodeIfPresent(Int.self, forKey: .historyLimit) ?? 5
        modelPresets = try c.decodeIfPresent([String: [ModelPreset]].self, forKey: .modelPresets) ?? [:]
    }

    static var `default`: AppConfig {
        AppConfig(
            schemaVersion: 1,
            hotkeyKeyCode: Int(kVK_Space),
            hotkeyModifiers: Int(cmdKey | shiftKey),
            actions: [
                Action(
                    name: "Přeložit do češtiny",
                    systemPrompt: "Přelož následující text do češtiny. Odpověz pouze překladem.",
                    provider: .anthropic,
                    model: "claude-sonnet-4-6",
                    enabled: true,
                    temperature: 0.1
                ),
                Action(
                    name: "Přepsat + gramatika",
                    systemPrompt: "Přepiš následující text tak, aby byl srozumitelnější a gramaticky správný. Zachovej původní jazyk. Odpověz pouze přepsaným textem. Nepřidávej žádné další informace navíc.",
                    provider: .openai,
                    model: "gpt-5.4-mini",
                    enabled: true,
                    temperature: 0.2
                ),
                Action(
                    name: "Zjednoduš a vysvětli",
                    systemPrompt: "Vysvětli následující text jednoduše pro zaneprázdněného profesionála.\nBuď stručný a zaměř se na praktické pochopení.",
                    provider: .openai,
                    model: "gpt-5.4-mini",
                    enabled: true,
                    temperature: 0.5
                ),
                Action(
                    name: "Shrň do odrážek",
                    systemPrompt: "Shrň následující text do:\n- 3 hlavních bodů\n- 1 krátké shrnující věty\n- důležitých entit (pokud existují)\nNepřidávej žádné další informace navíc.",
                    provider: .openai,
                    model: "gpt-5.4-mini",
                    enabled: true,
                    temperature: 0.2
                ),
                Action(
                    name: "Připrav odpověď",
                    systemPrompt: "Napiš stručnou a profesionální odpověď na následující zprávu.\nStyl: neutrální, zdvořilý  \nDélka: krátká",
                    provider: .openai,
                    model: "gpt-5.5",
                    enabled: true,
                    temperature: 0.5
                )
            ]
        )
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
        case .useGlobal: "Dle nastavení"
        case .always:    "Vždy"
        case .never:     "Nikdy"
        }
    }
}

enum ProviderType: String, Codable, CaseIterable {
    case openai
    case azureOpenai = "azure_openai"
    case azureOpenai2 = "azure_openai_2"
    case anthropic
    case customOpenAI = "custom_openai"
    case customOpenAI2 = "custom_openai_2"
}
