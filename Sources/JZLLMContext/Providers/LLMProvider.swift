import Foundation

protocol LLMProvider: Sendable {
    func stream(systemPrompt: String, userContent: String) -> AsyncThrowingStream<String, Error>
}

enum LLMError: Error, LocalizedError {
    case missingAPIKey(ProviderType)
    case httpError(Int, String)
    case networkError(Error)
    case decodingError
    /// The model hit the token limit; the partial text has already been streamed.
    case truncated(maxTokens: Int)
    /// The provider refused to answer (Anthropic `refusal`, OpenAI `content_filter`).
    case refused
    /// The provider reported an error after the stream had started.
    case streamError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let p):
            if p == .openai      { return "Chybí API klíč pro OpenAI. Přidej ho v Nastavení → Providery." }
            if p == .azureOpenai  { return "Chybí API klíč nebo konfigurace pro Azure AI (slot 1). Přidej ho v Nastavení → Providery." }
            if p == .azureOpenai2 { return "Chybí API klíč nebo konfigurace pro Azure AI (slot 2). Přidej ho v Nastavení → Providery." }
            if p == .anthropic    { return "Chybí API klíč pro Anthropic. Přidej ho v Nastavení → Providery." }
            if p == .gemini       { return "Chybí API klíč pro Google Gemini. Přidej ho v Nastavení → Providery." }
            if p == .grok         { return "Chybí API klíč pro xAI Grok. Přidej ho v Nastavení → Providery." }
            let name = p.customProvider?.name ?? p.rawValue
            return "Chybí konfigurace pro \(name). Nakonfiguruj ho v Nastavení → Providery."
        case .httpError(let code, let message): return "API chyba \(code): \(message)"
        case .networkError(let error): return "Síťová chyba: \(error.localizedDescription)"
        case .decodingError: return "Chyba při zpracování odpovědi"
        case .truncated(let maxTokens): return String(format: L("error.truncated"), maxTokens)
        case .refused: return L("error.refused")
        case .streamError(let message): return String(format: L("error.stream"), message)
        }
    }
}
