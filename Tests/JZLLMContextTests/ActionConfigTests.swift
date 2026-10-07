import Foundation
import Testing
@testable import JZLLMContext

/// Which parameters an action actually sends, and the schema 2 → 4 config migration.
struct ActionConfigTests {
    private let customProvider = ProviderType(UUID().uuidString)

    private func action(_ provider: ProviderType, temperature: Double? = nil,
                        effort: ReasoningEffort? = nil) -> Action {
        Action(name: "a", systemPrompt: "s", provider: provider, model: "m", enabled: true,
               temperature: temperature, reasoningEffort: effort)
    }

    @Test(arguments: ProviderType.builtIn)
    func cloudProvidersNeverGetTemperature(provider: ProviderType) {
        #expect(action(provider, temperature: 0.5).effectiveTemperature == nil)
    }

    @Test func customProviderGetsTemperatureOnlyWhenSet() {
        #expect(action(customProvider, temperature: 0.5).effectiveTemperature == 0.5)
        #expect(action(customProvider).effectiveTemperature == nil)
    }

    @Test func reasoningEffortIsFilteredPerProvider() {
        #expect(action(.openai, effort: .off).effectiveReasoningEffort == .off)
        #expect(action(.azureOpenai, effort: .high).effectiveReasoningEffort == .high)
        #expect(action(customProvider, effort: .off).effectiveReasoningEffort == .off)
        // Anthropic and Gemini can't turn reasoning off; Grok doesn't take the parameter
        #expect(action(.anthropic, effort: .off).effectiveReasoningEffort == nil)
        #expect(action(.anthropic, effort: .low).effectiveReasoningEffort == .low)
        #expect(action(.gemini, effort: .off).effectiveReasoningEffort == nil)
        #expect(action(.grok, effort: .low).effectiveReasoningEffort == nil)
    }

    @Test func offEncodesAsNone() throws {
        let data = try JSONEncoder().encode(ReasoningEffort.off)
        #expect(String(decoding: data, as: UTF8.self) == #""none""#)
    }

    @Test func schema2ConfigMigrates() throws {
        let customID = customProvider.rawValue
        let json = """
        {
          "schemaVersion": 2,
          "hotkeyKeyCode": 49,
          "hotkeyModifiers": 768,
          "actions": [
            { "id": "\(UUID().uuidString)", "name": "cloud", "systemPrompt": "s", "provider": "openai",
              "model": "gpt-5.5", "enabled": true, "temperature": 0.5, "maxTokens": 2048 },
            { "id": "\(UUID().uuidString)", "name": "custom", "systemPrompt": "s", "provider": "\(customID)",
              "model": "llama", "enabled": true, "temperature": 0.3, "maxTokens": 4000 },
            { "id": "\(UUID().uuidString)", "name": "bare", "systemPrompt": "s", "provider": "anthropic",
              "model": "claude-sonnet-4-6", "enabled": true }
          ]
        }
        """
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.schemaVersion == 4)

        let cloud = config.actions[0]
        #expect(cloud.temperature == nil)
        #expect(cloud.maxTokens == Action.defaultMaxTokens)
        #expect(cloud.reasoningEffort == nil)

        let custom = config.actions[1]
        #expect(custom.temperature == 0.3)
        #expect(custom.maxTokens == 4000)

        let bare = config.actions[2]
        #expect(bare.temperature == nil)
        #expect(bare.maxTokens == Action.defaultMaxTokens)
    }

    @Test func unknownReasoningEffortDecodesAsNil() throws {
        let json = """
        { "id": "\(UUID().uuidString)", "name": "a", "systemPrompt": "s", "provider": "openai",
          "model": "m", "enabled": true, "reasoningEffort": "xhigh" }
        """
        let action = try JSONDecoder().decode(Action.self, from: Data(json.utf8))
        #expect(action.reasoningEffort == nil)
    }

    @Test(arguments: [ProviderType.openai, .anthropic, .gemini, .grok])
    func presetsHaveExactlyOneRecommendedModel(provider: ProviderType) {
        #expect(provider.presetModels.filter(\.isRecommended).count == 1)
        #expect(provider.recommendedModelID != nil)
    }

    @Test func defaultActionsUsePresetModels() {
        for language in [AppLanguage.cs, .en, .es] {
            for action in AppConfig.makeDefault(language: language).actions {
                let presetIDs = action.provider.presetModels.map(\.id)
                #expect(presetIDs.contains(action.model), "\(action.name): \(action.model)")
            }
        }
    }

    @Test func defaultActionsSendNoTemperature() {
        for language in [AppLanguage.cs, .en, .es] {
            for action in AppConfig.makeDefault(language: language).actions {
                #expect(action.effectiveTemperature == nil, "\(action.name)")
            }
        }
    }
}
