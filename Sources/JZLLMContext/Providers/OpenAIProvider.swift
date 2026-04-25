import Foundation

struct OpenAIProvider: LLMProvider {
    let model: String
    let apiKey: String
    let baseURL: URL
    let temperature: Double
    let maxTokens: Int

    init(model: String, apiKey: String, baseURL: URL = URL(string: "https://api.openai.com/v1")!, temperature: Double = 0.7, maxTokens: Int = 4096) {
        self.model = model
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.temperature = temperature
        self.maxTokens = maxTokens
    }

    func complete(systemPrompt: String, userContent: String) async throws -> String {
        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = OpenAIChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userContent)
            ],
            temperature: temperature,
            maxTokens: maxTokens
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw LLMError.decodingError }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data))?.error.message ?? String(data: data, encoding: .utf8) ?? ""
            throw LLMError.httpError(http.statusCode, message)
        }

        guard let result = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data),
              let content = result.choices.first?.message.content
        else { throw LLMError.decodingError }

        return content
    }
}

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int
    struct Message: Encodable {
        let role: String
        let content: String
    }
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

private struct OpenAIChatResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let message: Message
        struct Message: Decodable {
            let content: String
        }
    }
}

private struct OpenAIErrorResponse: Decodable {
    let error: APIError
    struct APIError: Decodable {
        let message: String
    }
}
