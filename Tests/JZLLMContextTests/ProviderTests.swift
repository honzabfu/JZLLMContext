import Foundation
import Testing
@testable import JZLLMContext

/// Request bodies and stream parsing of the providers against a mocked network.
/// Serialized: the mock is process-wide state shared by every request — and it
/// would intercept the live calls, so the suite is off when those run.
@Suite(.serialized, .disabled(if: liveAPITestsEnabled))
struct ProviderTests {
    private static let chatURL = URL(string: "https://mock.test/v1/chat/completions")!

    init() {
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    private func collect(_ stream: AsyncThrowingStream<String, Error>) async -> (text: String, error: Error?) {
        var text = ""
        do {
            for try await chunk in stream { text += chunk }
            return (text, nil)
        } catch {
            return (text, error)
        }
    }

    private func openAI(temperature: Double? = nil, effort: ReasoningEffort? = nil,
                        maxTokens: Int = 100) -> OpenAIProvider {
        OpenAIProvider(model: "gpt-5.5", apiKey: "test", chatURL: Self.chatURL,
                       temperature: temperature, reasoningEffort: effort, maxTokens: maxTokens)
    }

    private func anthropic(effort: ReasoningEffort? = nil, maxTokens: Int = 100) -> AnthropicProvider {
        AnthropicProvider(model: "claude-sonnet-5-5", apiKey: "test", maxTokens: maxTokens, effort: effort)
    }

    private static let openAIDone = [
        #"{"choices":[{"index":0,"delta":{"content":"Ahoj"},"finish_reason":null}]}"#,
        #"{"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#,
        "[DONE]"
    ]

    private static let anthropicDone = [
        #"{"type":"message_start","message":{"id":"m"}}"#,
        #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Ahoj"}}"#,
        #"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#,
        #"{"type":"message_stop"}"#
    ]

    // MARK: - OpenAI-compatible request body

    @Test func openAIOmitsTemperatureAndEffortWhenNil() async {
        MockURLProtocol.stubStream(Self.openAIDone)
        let result = await collect(openAI().stream(systemPrompt: "s", userContent: "u"))
        #expect(result.text == "Ahoj")
        #expect(result.error == nil)
        let body = try! #require(MockURLProtocol.lastRequestJSON)
        #expect(body["temperature"] == nil)
        #expect(body["reasoning_effort"] == nil)
        #expect(body["max_completion_tokens"] as? Int == 100)
    }

    @Test func openAISendsTemperatureAndEffortWhenSet() async {
        MockURLProtocol.stubStream(Self.openAIDone)
        _ = await collect(openAI(temperature: 0.3, effort: .off).stream(systemPrompt: "s", userContent: "u"))
        let body = try! #require(MockURLProtocol.lastRequestJSON)
        #expect(body["temperature"] as? Double == 0.3)
        #expect(body["reasoning_effort"] as? String == "none")
    }

    // MARK: - OpenAI-compatible stream end

    @Test func openAILengthKeepsTextAndThrowsTruncated() async {
        MockURLProtocol.stubStream([
            #"{"choices":[{"index":0,"delta":{"content":"Částečný"},"finish_reason":null}]}"#,
            #"{"choices":[{"index":0,"delta":{},"finish_reason":"length"}]}"#,
            "[DONE]"
        ])
        let result = await collect(openAI(maxTokens: 256).stream(systemPrompt: "s", userContent: "u"))
        #expect(result.text == "Částečný")
        guard case .truncated(let maxTokens)? = result.error as? LLMError else {
            Issue.record("expected .truncated, got \(String(describing: result.error))")
            return
        }
        #expect(maxTokens == 256)
    }

    @Test func openAIContentFilterThrowsRefused() async {
        MockURLProtocol.stubStream([
            #"{"choices":[{"index":0,"delta":{},"finish_reason":"content_filter"}]}"#,
            "[DONE]"
        ])
        let result = await collect(openAI().stream(systemPrompt: "s", userContent: "u"))
        guard case .refused? = result.error as? LLMError else {
            Issue.record("expected .refused, got \(String(describing: result.error))")
            return
        }
    }

    @Test func openAIMidStreamErrorThrowsStreamError() async {
        MockURLProtocol.stubStream([
            #"{"choices":[{"index":0,"delta":{"content":"Za"},"finish_reason":null}]}"#,
            #"{"error":{"message":"Server overloaded","type":"server_error"}}"#
        ])
        let result = await collect(openAI().stream(systemPrompt: "s", userContent: "u"))
        #expect(result.text == "Za")
        guard case .streamError(let message)? = result.error as? LLMError else {
            Issue.record("expected .streamError, got \(String(describing: result.error))")
            return
        }
        #expect(message == "Server overloaded")
    }

    @Test func openAIUsageOnlyChunkIsIgnored() async {
        MockURLProtocol.stubStream([
            #"{"choices":[{"index":0,"delta":{"content":"Ahoj"},"finish_reason":"stop"}]}"#,
            #"{"choices":[],"usage":{"total_tokens":5}}"#,
            "[DONE]"
        ])
        let result = await collect(openAI().stream(systemPrompt: "s", userContent: "u"))
        #expect(result.text == "Ahoj")
        #expect(result.error == nil)
    }

    // MARK: - OpenAI-compatible HTTP errors

    @Test func temperature400GetsHint() async {
        let apiMessage = "Unsupported parameter: 'temperature' is not supported with this model."
        MockURLProtocol.stub(status: 400, body: #"{"error":{"message":"\#(apiMessage)"}}"#)
        let result = await collect(openAI(temperature: 0.5).stream(systemPrompt: "s", userContent: "u"))
        guard case .httpError(let code, let message)? = result.error as? LLMError else {
            Issue.record("expected .httpError, got \(String(describing: result.error))")
            return
        }
        #expect(code == 400)
        #expect(message.hasPrefix(apiMessage))
        #expect(message.contains(L("error.hint.disable_temperature")))
    }

    @Test func temperature400WithoutTemperatureSentHasNoHint() async {
        let apiMessage = "Unsupported parameter: 'temperature'."
        MockURLProtocol.stub(status: 400, body: #"{"error":{"message":"\#(apiMessage)"}}"#)
        let result = await collect(openAI().stream(systemPrompt: "s", userContent: "u"))
        guard case .httpError(_, let message)? = result.error as? LLMError else {
            Issue.record("expected .httpError, got \(String(describing: result.error))")
            return
        }
        #expect(message == apiMessage)
    }

    @Test func reasoning400GetsHint() async {
        MockURLProtocol.stub(status: 400, body: #"{"error":{"message":"Unsupported value: 'reasoning_effort' does not support 'none' with this model."}}"#)
        let result = await collect(openAI(effort: .off).stream(systemPrompt: "s", userContent: "u"))
        guard case .httpError(_, let message)? = result.error as? LLMError else {
            Issue.record("expected .httpError, got \(String(describing: result.error))")
            return
        }
        #expect(message.contains(L("error.hint.reset_reasoning")))
    }

    // MARK: - Anthropic

    @Test func anthropicRequestHasNoTemperatureAndOptionalEffort() async {
        MockURLProtocol.stubStream(Self.anthropicDone)
        let result = await collect(anthropic().stream(systemPrompt: "s", userContent: "u"))
        #expect(result.text == "Ahoj")
        #expect(result.error == nil)
        var body = try! #require(MockURLProtocol.lastRequestJSON)
        #expect(body["temperature"] == nil)
        #expect(body["output_config"] == nil)
        #expect(body["max_tokens"] as? Int == 100)

        MockURLProtocol.stubStream(Self.anthropicDone)
        _ = await collect(anthropic(effort: .medium).stream(systemPrompt: "s", userContent: "u"))
        body = try! #require(MockURLProtocol.lastRequestJSON)
        let outputConfig = body["output_config"] as? [String: Any]
        #expect(outputConfig?["effort"] as? String == "medium")
    }

    @Test func anthropicMaxTokensThrowsTruncated() async {
        MockURLProtocol.stubStream([
            #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Část"}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#,
            #"{"type":"message_stop"}"#
        ])
        let result = await collect(anthropic(maxTokens: 512).stream(systemPrompt: "s", userContent: "u"))
        #expect(result.text == "Část")
        guard case .truncated(let maxTokens)? = result.error as? LLMError else {
            Issue.record("expected .truncated, got \(String(describing: result.error))")
            return
        }
        #expect(maxTokens == 512)
    }

    @Test func anthropicRefusalThrowsRefused() async {
        MockURLProtocol.stubStream([
            #"{"type":"message_delta","delta":{"stop_reason":"refusal"}}"#,
            #"{"type":"message_stop"}"#
        ])
        let result = await collect(anthropic().stream(systemPrompt: "s", userContent: "u"))
        guard case .refused? = result.error as? LLMError else {
            Issue.record("expected .refused, got \(String(describing: result.error))")
            return
        }
    }

    @Test func anthropicErrorEventThrowsStreamError() async {
        MockURLProtocol.stubStream([
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Za"}}"#,
            #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        ])
        let result = await collect(anthropic().stream(systemPrompt: "s", userContent: "u"))
        #expect(result.text == "Za")
        guard case .streamError(let message)? = result.error as? LLMError else {
            Issue.record("expected .streamError, got \(String(describing: result.error))")
            return
        }
        #expect(message == "Overloaded")
    }

    @Test func anthropicEffort400GetsHint() async {
        MockURLProtocol.stub(status: 400, body: #"{"type":"error","error":{"type":"invalid_request_error","message":"output_config.effort: This model does not support the effort parameter."}}"#)
        let result = await collect(anthropic(effort: .low).stream(systemPrompt: "s", userContent: "u"))
        guard case .httpError(_, let message)? = result.error as? LLMError else {
            Issue.record("expected .httpError, got \(String(describing: result.error))")
            return
        }
        #expect(message.contains(L("error.hint.reset_reasoning")))
    }
}
