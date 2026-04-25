import Foundation

struct AnthropicProvider: LLMProvider {
    let model: String
    let apiKey: String
    let temperature: Double
    let maxTokens: Int

    func complete(systemPrompt: String, userContent: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let body = AnthropicRequest(
            model: model,
            maxTokens: maxTokens,
            temperature: min(temperature, 1.0),
            system: systemPrompt,
            messages: [.init(role: "user", content: userContent)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw LLMError.decodingError }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data))?.error.message ?? String(data: data, encoding: .utf8) ?? ""
            throw LLMError.httpError(http.statusCode, message)
        }

        guard let result = try? JSONDecoder().decode(AnthropicResponse.self, from: data),
              let text = result.content.first?.text
        else { throw LLMError.decodingError }

        return text
    }
}

private struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let temperature: Double
    let system: String
    let messages: [Message]
    struct Message: Encodable {
        let role: String
        let content: String
    }
    enum CodingKeys: String, CodingKey {
        case model, temperature, system, messages
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicResponse: Decodable {
    let content: [ContentBlock]
    struct ContentBlock: Decodable {
        let text: String
    }
}

private struct AnthropicErrorResponse: Decodable {
    let error: APIError
    struct APIError: Decodable {
        let message: String
    }
}
