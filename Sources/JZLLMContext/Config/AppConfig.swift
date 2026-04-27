import Carbon
import Foundation

struct AppConfig: Codable {
    var schemaVersion: Int
    var hotkeyKeyCode: Int
    var hotkeyModifiers: Int
    var actions: [Action]
    var azureEndpoint: String?
    var azureDeploymentName: String?
    var customOpenAIBaseURL: String?

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
                    enabled: true
                ),
                Action(
                    name: "Přepsat + gramatika",
                    systemPrompt: "Přepiš následující text tak, aby byl srozumitelnější a gramaticky správný. Zachovej původní jazyk. Odpověz pouze přepsaným textem. Nepřidávej žádné další informace navíc.",
                    provider: .openai,
                    model: "gpt-4o",
                    enabled: true
                ),
                Action(
                    name: "Zjednoduš a vysvětli",
                    systemPrompt: "Vysvětli následující text jednoduše pro zaneprázdněného profesionála.\nBuď stručný a zaměř se na praktické pochopení.",
                    provider: .openai,
                    model: "gpt-4o",
                    enabled: true
                ),
                Action(
                    name: "Shrň do odrážek",
                    systemPrompt: "Shrň následující text do:\n- 3 hlavních bodů\n- 1 krátké shrnující věty\n- důležitých entit (pokud existují)\nNepřidávej žádné další informace navíc.",
                    provider: .openai,
                    model: "gpt-4o",
                    enabled: true
                ),
                Action(
                    name: "Připrav odpověď",
                    systemPrompt: "Napiš stručnou a profesionální odpověď na následující zprávu.\nStyl: neutrální, zdvořilý  \nDélka: krátká",
                    provider: .openai,
                    model: "gpt-4o",
                    enabled: true
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

    init(
        name: String,
        systemPrompt: String,
        provider: ProviderType,
        model: String,
        enabled: Bool,
        temperature: Double = 0.7,
        maxTokens: Int = 4096
    ) {
        self.id = UUID()
        self.name = name
        self.systemPrompt = systemPrompt
        self.provider = provider
        self.model = model
        self.enabled = enabled
        self.temperature = temperature
        self.maxTokens = maxTokens
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
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 4096
    }
}

enum ProviderType: String, Codable, CaseIterable {
    case openai
    case azureOpenai = "azure_openai"
    case anthropic
    case customOpenAI = "custom_openai"
}
