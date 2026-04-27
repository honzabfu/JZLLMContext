import Foundation

struct AnthropicProvider: LLMProvider {
    let model: String
    let apiKey: String
    let temperature: Double
    let maxTokens: Int

    func stream(systemPrompt: String, userContent: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let url = URL(string: "https://api.anthropic.com/v1/messages")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.timeoutInterval = 60

                    let body = AnthropicRequest(
                        model: model,
                        maxTokens: maxTokens,
                        temperature: min(temperature, 1.0),
                        system: systemPrompt,
                        messages: [.init(role: "user", content: userContent)]
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
                        let message = (try? JSONDecoder().decode(AnthropicErrorResponse.self, from: errorData))?.error.message
                            ?? String(data: errorData, encoding: .utf8) ?? ""
                        continuation.finish(throwing: LLMError.httpError(http.statusCode, message))
                        return
                    }

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let payload = String(line.dropFirst(6))
                            if let data = payload.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(AnthropicStreamChunk.self, from: data),
                               chunk.type == "content_block_delta",
                               chunk.delta?.type == "text_delta",
                               let text = chunk.delta?.text {
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

private struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let temperature: Double
    let system: String
    let messages: [Message]
    let stream: Bool = true
    struct Message: Encodable {
        let role: String
        let content: String
    }
    enum CodingKeys: String, CodingKey {
        case model, temperature, system, messages, stream
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicStreamChunk: Decodable {
    let type: String
    let delta: Delta?
    struct Delta: Decodable {
        let type: String?
        let text: String?
    }
}

private struct AnthropicErrorResponse: Decodable {
    let error: APIError
    struct APIError: Decodable {
        let message: String
    }
}
