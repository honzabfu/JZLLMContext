import Foundation

enum ProviderFactory {
    static func make(for action: Action) throws -> any LLMProvider {
        switch action.provider {
        case .openai:
            let apiKey = try KeychainStore.load(for: .openai)
            return OpenAIProvider(model: action.model, apiKey: apiKey, temperature: action.temperature, maxTokens: action.maxTokens)

        case .azureOpenai:
            let apiKey = try KeychainStore.load(for: .azureOpenai)
            let config = ConfigStore.shared.config
            guard let endpointStr = config.azureEndpoint,
                  let deploymentName = config.azureDeploymentName,
                  let baseURL = URL(string: "\(endpointStr)/openai/deployments/\(deploymentName)")
            else { throw LLMError.missingAPIKey(.azureOpenai) }
            return OpenAIProvider(model: action.model, apiKey: apiKey, baseURL: baseURL, temperature: action.temperature, maxTokens: action.maxTokens)

        case .anthropic:
            let apiKey = try KeychainStore.load(for: .anthropic)
            return AnthropicProvider(model: action.model, apiKey: apiKey, temperature: action.temperature, maxTokens: action.maxTokens)

        case .customOpenAI:
            let apiKey = (try? KeychainStore.load(for: .customOpenAI)) ?? ""
            let config = ConfigStore.shared.config
            guard let urlStr = config.customOpenAIBaseURL, !urlStr.isEmpty,
                  let baseURL = URL(string: urlStr)
            else { throw LLMError.missingAPIKey(.customOpenAI) }
            return OpenAIProvider(model: action.model, apiKey: apiKey, baseURL: baseURL, temperature: action.temperature, maxTokens: action.maxTokens)
        }
    }
}
