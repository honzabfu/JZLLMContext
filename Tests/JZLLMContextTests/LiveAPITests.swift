import Foundation
import Testing
@testable import JZLLMContext

/// Opt-in live calls against the real provider APIs, using the API keys and provider
/// settings the app has stored (read-only). Costs real tokens, so it only runs with
///
///     TEST_RUNNER_LIVE_API_TESTS=1 xcodebuild test -scheme JZLLMContext \
///         -destination 'platform=macOS' -only-testing:JZLLMContextTests/LiveAPITests
///
/// Each case prints a `LIVE|` line; providers without a key are skipped.
let liveAPITestsEnabled = ProcessInfo.processInfo.environment["LIVE_API_TESTS"] == "1"

@Suite(.enabled(if: liveAPITestsEnabled))
struct LiveAPITests {
    enum Expectation: Sendable {
        case text          // complete answer, no error
        case truncated     // partial text + LLMError.truncated
        case httpError400  // request rejected (premise / hint checks)
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let provider: ProviderType
        let model: String
        var effort: ReasoningEffort? = nil
        var maxTokens: Int = 1024
        let expect: Expectation
        /// Sends a temperature directly through `OpenAIProvider`, bypassing the
        /// factory (which never sends one to cloud providers) — premise check only.
        var rawTemperature: Double? = nil

        var testDescription: String {
            var parts = [provider.rawValue, model, "effort=\(effort?.rawValue ?? "default")", "max=\(maxTokens)"]
            if let rawTemperature { parts.append("temperature=\(rawTemperature)") }
            return parts.joined(separator: " ")
        }
    }

    static let cases: [Case] = [
        // OpenAI
        Case(provider: .openai, model: "gpt-5.5", expect: .text),
        Case(provider: .openai, model: "gpt-5.5", effort: .off, expect: .text),
        Case(provider: .openai, model: "gpt-5.5", effort: .low, expect: .text),
        Case(provider: .openai, model: "gpt-5.4-mini", expect: .text),
        Case(provider: .openai, model: "gpt-5.4-mini", maxTokens: 16, expect: .truncated),
        Case(provider: .openai, model: "gpt-5.5", expect: .httpError400, rawTemperature: 0.5),
        Case(provider: .openai, model: "o4-mini", effort: .off, expect: .httpError400),
        Case(provider: .openai, model: "gpt-6-sol", expect: .text),
        Case(provider: .openai, model: "gpt-6-sol", effort: .low, expect: .text),
        Case(provider: .openai, model: "gpt-6-luna", expect: .text),
        Case(provider: .openai, model: "gpt-6-luna", effort: .off, expect: .text),
        Case(provider: .openai, model: "gpt-6-sol", expect: .httpError400, rawTemperature: 0.5),
        // Anthropic
        Case(provider: .anthropic, model: "claude-sonnet-4-6", expect: .text),
        Case(provider: .anthropic, model: "claude-sonnet-4-6", effort: .low, expect: .text),
        Case(provider: .anthropic, model: "claude-sonnet-4-6", maxTokens: 16, expect: .truncated),
        Case(provider: .anthropic, model: "claude-sonnet-5-5", expect: .text),
        Case(provider: .anthropic, model: "claude-sonnet-5-5", effort: .low, expect: .text),
        Case(provider: .anthropic, model: "claude-haiku-4-5-20251001", expect: .text),
        Case(provider: .anthropic, model: "claude-haiku-4-5-20251001", effort: .low, expect: .httpError400),
        // Gemini
        Case(provider: .gemini, model: "gemini-3.1-flash-lite", expect: .text),
        Case(provider: .gemini, model: "gemini-3.1-flash-lite", effort: .low, expect: .text),
        Case(provider: .gemini, model: "gemini-flash-latest", effort: .medium, expect: .text),
        Case(provider: .gemini, model: "gemini-3.1-pro-preview", expect: .text),
        Case(provider: .gemini, model: "gemini-3.5-flash-lite", expect: .text),
        Case(provider: .gemini, model: "gemini-3.8-flash", expect: .text),
        Case(provider: .gemini, model: "gemini-3.8-flash", effort: .low, expect: .text),
        // Grok
        Case(provider: .grok, model: "grok-4.20", expect: .text),
        Case(provider: .grok, model: "grok-4.20-non-reasoning", maxTokens: 16, expect: .truncated)
    ]

    private static let systemPrompt = "Answer in one short sentence."
    private static let input = "What is the capital of the Czech Republic?"
    private static let longInput = "Write a detailed 500-word essay about the history of Prague."

    @Test(arguments: cases)
    func matrix(_ testCase: Case) async {
        guard KeychainStore.hasKey(for: testCase.provider) else {
            print("LIVE| SKIP  \(testCase.testDescription) — no API key")
            return
        }
        let provider: any LLMProvider
        do {
            if let temperature = testCase.rawTemperature {
                provider = OpenAIProvider(model: testCase.model, apiKey: try KeychainStore.load(for: .openai),
                                          temperature: temperature, maxTokens: testCase.maxTokens)
            } else {
                var action = Action(name: "live", systemPrompt: Self.systemPrompt, provider: testCase.provider,
                                    model: testCase.model, enabled: true, maxTokens: testCase.maxTokens)
                action.reasoningEffort = testCase.effort
                provider = try ProviderFactory.make(for: action)
            }
        } catch {
            print("LIVE| SKIP  \(testCase.testDescription) — \(error.localizedDescription)")
            return
        }

        let userInput = testCase.expect == .truncated ? Self.longInput : Self.input
        let (text, error) = await run(provider, input: userInput)
        let outcome = Self.describe(text: text, error: error)

        let passed: Bool
        switch testCase.expect {
        case .text:
            passed = error == nil && !text.isEmpty
        case .truncated:
            if case .truncated? = error as? LLMError { passed = !text.isEmpty } else { passed = false }
        case .httpError400:
            if case .httpError(400, _)? = error as? LLMError { passed = true } else { passed = false }
        }
        print("LIVE| \(passed ? "OK  " : "FAIL") \(testCase.testDescription) → \(outcome)")
        #expect(passed, "\(testCase.testDescription) → \(outcome)")
    }

    /// Compares the built-in presets and default actions with each provider's live
    /// model list (free, read-only `/models` calls).
    @Test func presetModelsExist() async {
        let defaultModels = Set(AppConfig.makeDefault(language: .cs).actions.map { "\($0.provider.rawValue)|\($0.model)" })
        for provider in ProviderType.builtIn where KeychainStore.hasKey(for: provider) {
            let fetched: [FetchedModel]
            do {
                fetched = try await ModelFetcher.fetch(for: provider)
            } catch {
                print("MODELS| \(provider.rawValue): fetch failed — \(error.localizedDescription)")
                continue
            }
            // Models used by an action are appended even when the provider doesn't list
            // them, so in-use presets are only reported as "in use", not as listed
            let available = fetched.filter { !$0.inUseByAction }
            let ids = Set(available.map(\.id))
            func exists(_ id: String) -> Bool {
                ids.contains(id) || ids.contains("models/\(id)")
            }
            print("MODELS| \(provider.rawValue): \(available.count) listed: \(available.map(\.id).prefix(40).joined(separator: ", "))")
            for preset in provider.presetModels {
                let mark = preset.isRecommended ? " (recommended)" : ""
                let inUse = fetched.contains { $0.id == preset.id && $0.inUseByAction }
                print("MODELS| \(provider.rawValue): preset \(preset.id)\(mark) → \(exists(preset.id) ? "listed" : inUse ? "in use (unverified)" : "NOT LISTED")")
                #expect(exists(preset.id) || inUse, "\(provider.rawValue) preset \(preset.id) is not offered by the provider")
            }
            for entry in defaultModels where entry.hasPrefix("\(provider.rawValue)|") {
                let id = String(entry.dropFirst(provider.rawValue.count + 1))
                print("MODELS| \(provider.rawValue): default action \(id) → \(exists(id) ? "listed" : "NOT LISTED")")
                #expect(exists(id) || fetched.contains { $0.id == id }, "\(provider.rawValue) default action model \(id) is not offered")
            }
        }
    }

    /// Every enabled action from the user's real config, with a short input.
    @Test func configuredActions() async {
        for action in ConfigStore.shared.actions where action.enabled {
            let label = "action '\(action.name)' \(action.provider.displayName) \(action.model)"
                + " effort=\(action.effectiveReasoningEffort?.rawValue ?? "default")"
                + " temperature=\(action.effectiveTemperature.map { String($0) } ?? "—")"
                + " max=\(action.maxTokens)"
            let provider: any LLMProvider
            do {
                provider = try ProviderFactory.make(for: action)
            } catch {
                print("LIVE| SKIP  \(label) — \(error.localizedDescription)")
                continue
            }
            let (text, error) = await run(provider, input: "Ahoj, tohle je krátký test. Odpověz jednou větou.",
                                          systemPrompt: action.systemPrompt)
            let ok = error == nil && !text.isEmpty
            print("LIVE| \(ok ? "OK  " : "WARN") \(label) → \(Self.describe(text: text, error: error))")
        }
    }

    private func run(_ provider: any LLMProvider, input: String,
                     systemPrompt: String = LiveAPITests.systemPrompt) async -> (String, Error?) {
        var text = ""
        do {
            for try await chunk in provider.stream(systemPrompt: systemPrompt, userContent: input) {
                text += chunk
            }
            return (text, nil)
        } catch {
            return (text, error)
        }
    }

    private static func describe(text: String, error: Error?) -> String {
        let snippet = text.replacingOccurrences(of: "\n", with: " ").prefix(70)
        guard let error else { return "text(\(text.count)): \(snippet)" }
        let message = error.localizedDescription.replacingOccurrences(of: "\n", with: " ⏎ ")
        return "ERROR \(message)" + (text.isEmpty ? "" : " | partial(\(text.count)): \(snippet)")
    }
}
