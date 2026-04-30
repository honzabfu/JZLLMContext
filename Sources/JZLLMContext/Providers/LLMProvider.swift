import Foundation

protocol LLMProvider: Sendable {
    func stream(systemPrompt: String, userContent: String) -> AsyncThrowingStream<String, Error>
}

enum LLMError: Error, LocalizedError {
    case missingAPIKey(ProviderType)
    case httpError(Int, String)
    case networkError(Error)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            switch provider {
            case .customOpenAI:   "Chybí Base URL pro Vlastní API (slot 1). Nakonfiguruj ho v Nastavení → Providery."
            case .customOpenAI2:  "Chybí Base URL pro Vlastní API (slot 2). Nakonfiguruj ho v Nastavení → Providery."
            case .openai:         "Chybí API klíč pro OpenAI. Přidej ho v Nastavení → Providery."
            case .azureOpenai:    "Chybí API klíč nebo konfigurace pro Azure AI (slot 1). Přidej ho v Nastavení → Providery."
            case .azureOpenai2:   "Chybí API klíč nebo konfigurace pro Azure AI (slot 2). Přidej ho v Nastavení → Providery."
            case .anthropic:      "Chybí API klíč pro Anthropic. Přidej ho v Nastavení → Providery."
            case .gemini:         "Chybí API klíč pro Google Gemini. Přidej ho v Nastavení → Providery."
            case .grok:           "Chybí API klíč pro xAI Grok. Přidej ho v Nastavení → Providery."
            }
        case .httpError(let code, let message): "API chyba \(code): \(message)"
        case .networkError(let error): "Síťová chyba: \(error.localizedDescription)"
        case .decodingError: "Chyba při zpracování odpovědi"
        }
    }
}
