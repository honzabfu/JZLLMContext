import Foundation

protocol LLMProvider {
    func complete(systemPrompt: String, userContent: String) async throws -> String
}

enum LLMError: Error, LocalizedError {
    case missingAPIKey(ProviderType)
    case httpError(Int, String)
    case networkError(Error)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            provider == .customOpenAI
                ? "Chybí Base URL pro vlastní OpenAI-compatible provider"
                : "Chybí API klíč pro \(provider.rawValue)"
        case .httpError(let code, let message): "API chyba \(code): \(message)"
        case .networkError(let error): "Síťová chyba: \(error.localizedDescription)"
        case .decodingError: "Chyba při zpracování odpovědi"
        }
    }
}
