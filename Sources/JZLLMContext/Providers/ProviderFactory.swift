import Foundation

enum ProviderFactory {
    static func make(for action: Action) throws -> any LLMProvider {
        switch action.provider {
        case .openai:
            guard let apiKey = try? KeychainStore.load(for: .openai) else {
                throw LLMError.missingAPIKey(.openai)
            }
            return OpenAIProvider(model: action.model, apiKey: apiKey, temperature: action.temperature,
                                  maxTokens: action.maxTokens, tokenParamStyle: .maxCompletionTokens)

        case .azureOpenai:
            guard let apiKey = try? KeychainStore.load(for: .azureOpenai) else {
                throw LLMError.missingAPIKey(.azureOpenai)
            }
            let config = ConfigStore.shared.config
            guard let endpointStr = config.azureEndpoint, !endpointStr.isEmpty else {
                throw LLMError.missingAPIKey(.azureOpenai)
            }
            let chatURL = try azureChatURL(deploymentBase: endpointStr,
                                           legacyDeployment: config.azureDeploymentName,
                                           apiVersion: config.azureAPIVersion ?? AppConfig.defaultAzureAPIVersion)
            return OpenAIProvider(model: action.model, apiKey: apiKey, chatURL: chatURL,
                                  authStyle: .apiKey, temperature: action.temperature,
                                  maxTokens: action.maxTokens, tokenParamStyle: .maxCompletionTokens)

        case .azureOpenai2:
            guard let apiKey = try? KeychainStore.load(for: .azureOpenai2) else {
                throw LLMError.missingAPIKey(.azureOpenai2)
            }
            let config = ConfigStore.shared.config
            guard let endpointStr = config.azureEndpoint2, !endpointStr.isEmpty else {
                throw LLMError.missingAPIKey(.azureOpenai2)
            }
            let chatURL2 = try azureChatURL(deploymentBase: endpointStr,
                                            legacyDeployment: config.azureDeploymentName2,
                                            apiVersion: config.azureAPIVersion2 ?? AppConfig.defaultAzureAPIVersion)
            return OpenAIProvider(model: action.model, apiKey: apiKey, chatURL: chatURL2,
                                  authStyle: .apiKey, temperature: action.temperature,
                                  maxTokens: action.maxTokens, tokenParamStyle: .maxCompletionTokens)

        case .anthropic:
            guard let apiKey = try? KeychainStore.load(for: .anthropic) else {
                throw LLMError.missingAPIKey(.anthropic)
            }
            return AnthropicProvider(model: action.model, apiKey: apiKey, temperature: action.temperature, maxTokens: action.maxTokens)

        case .customOpenAI:
            let apiKey = (try? KeychainStore.load(for: .customOpenAI)) ?? ""
            let config = ConfigStore.shared.config
            guard let urlStr = config.customOpenAIBaseURL, !urlStr.isEmpty else {
                throw LLMError.missingAPIKey(.customOpenAI)
            }
            let chatURL = try customChatURL(baseURLStr: urlStr, apiVersion: config.customOpenAIAPIVersion, slot: .customOpenAI)
            return OpenAIProvider(model: action.model, apiKey: apiKey, chatURL: chatURL,
                                  authStyle: .bearer, temperature: action.temperature,
                                  maxTokens: action.maxTokens, tokenParamStyle: config.customOpenAITokenParam)

        case .customOpenAI2:
            let apiKey = (try? KeychainStore.load(for: .customOpenAI2)) ?? ""
            let config = ConfigStore.shared.config
            guard let urlStr = config.customOpenAIBaseURL2, !urlStr.isEmpty else {
                throw LLMError.missingAPIKey(.customOpenAI2)
            }
            let chatURL2 = try customChatURL(baseURLStr: urlStr, apiVersion: config.customOpenAIAPIVersion2, slot: .customOpenAI2)
            return OpenAIProvider(model: action.model, apiKey: apiKey, chatURL: chatURL2,
                                  authStyle: .bearer, temperature: action.temperature,
                                  maxTokens: action.maxTokens, tokenParamStyle: config.customOpenAITokenParam2)
        }
    }

    /// Builds the chat/completions URL for a custom OpenAI-compatible provider.
    /// Appends /chat/completions if not already present, and optionally ?api-version=…
    private static func customChatURL(baseURLStr: String, apiVersion: String?, slot: ProviderType) throws -> URL {
        var base = baseURLStr.hasSuffix("/") ? String(baseURLStr.dropLast()) : baseURLStr
        if !base.hasSuffix("/chat/completions") {
            base += "/chat/completions"
        }
        if let version = apiVersion, !version.isEmpty {
            var components = URLComponents(string: base)
            components?.queryItems = [URLQueryItem(name: "api-version", value: version)]
            guard let url = components?.url else { throw LLMError.missingAPIKey(slot) }
            return url
        }
        guard let url = URL(string: base) else { throw LLMError.missingAPIKey(slot) }
        return url
    }

    /// Builds the full chat/completions URL for an Azure deployment.
    /// If `deploymentBase` already contains "/deployments/" or "/chat/completions", use it directly.
    /// Otherwise fall back to legacy endpoint+deploymentName concatenation.
    private static func azureChatURL(deploymentBase: String, legacyDeployment: String?, apiVersion: String) throws -> URL {
        var base = deploymentBase.hasSuffix("/") ? String(deploymentBase.dropLast()) : deploymentBase

        // Strip trailing /chat/completions so we can re-add it uniformly
        if base.hasSuffix("/chat/completions") {
            base = String(base.dropLast("/chat/completions".count))
        }

        // If the user provided only the resource endpoint (no /deployments/ path),
        // fall back to legacy auto-construction using the separate deployment name field.
        if !base.contains("/deployments/") {
            guard let dep = legacyDeployment, !dep.isEmpty else {
                throw LLMError.missingAPIKey(.azureOpenai)
            }
            base = "\(base)/openai/deployments/\(dep)"
        }

        var components = URLComponents(string: "\(base)/chat/completions")
        components?.queryItems = [URLQueryItem(name: "api-version", value: apiVersion)]
        guard let url = components?.url else { throw LLMError.missingAPIKey(.azureOpenai) }
        return url
    }
}
