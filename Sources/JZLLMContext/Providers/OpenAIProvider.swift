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

    func stream(systemPrompt: String, userContent: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let url = baseURL.appendingPathComponent("chat/completions")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 60

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

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.decodingError)
                        return
                    }

                    guard (200..<300).contains(http.statusCode) else {
                        var errorData = Data()
                        for try await byte in bytes { errorData.append(byte) }
                        let message = (try? JSONDecoder().decode(OpenAIErrorResponse.self, from: errorData))?.error.message
                            ?? String(data: errorData, encoding: .utf8) ?? ""
                        continuation.finish(throwing: LLMError.httpError(http.statusCode, message))
                        return
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let payload = String(line.dropFirst(6))
                            if payload == "[DONE]" { break }
                            if let data = payload.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data),
                               let text = chunk.choices.first?.delta.content {
                                continuation.yield(text)
                            }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool = true
    struct Message: Encodable {
        let role: String
        let content: String
    }
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
}

private struct OpenAIStreamChunk: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let delta: Delta
        struct Delta: Decodable {
            let content: String?
        }
    }
}

private struct OpenAIErrorResponse: Decodable {
    let error: APIError
    struct APIError: Decodable {
        let message: String
    }
}
