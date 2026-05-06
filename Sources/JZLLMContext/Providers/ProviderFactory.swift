import Foundation

enum ProviderFactory {
    static func make(for action: Action) throws -> any LLMProvider {
        let provider = action.provider

        if provider == .openai {
            guard let apiKey = try? KeychainStore.load(for: .openai) else {
                throw LLMError.missingAPIKey(.openai)
            }
            return OpenAIProvider(model: action.model, apiKey: apiKey, temperature: action.temperature,
                                  maxTokens: action.maxTokens, tokenParamStyle: .maxCompletionTokens)

        } else if provider == .azureOpenai {
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

        } else if provider == .azureOpenai2 {
            guard let apiKey = try? KeychainStore.load(for: .azureOpenai2) else {
                throw LLMError.missingAPIKey(.azureOpenai2)
            }
            let config = ConfigStore.shared.config
            guard let endpointStr = config.azureEndpoint2, !endpointStr.isEmpty else {
                throw LLMError.missingAPIKey(.azureOpenai2)
            }
            let chatURL = try azureChatURL(deploymentBase: endpointStr,
                                           legacyDeployment: config.azureDeploymentName2,
                                           apiVersion: config.azureAPIVersion2 ?? AppConfig.defaultAzureAPIVersion)
            return OpenAIProvider(model: action.model, apiKey: apiKey, chatURL: chatURL,
                                  authStyle: .apiKey, temperature: action.temperature,
                                  maxTokens: action.maxTokens, tokenParamStyle: .maxCompletionTokens)

        } else if provider == .anthropic {
            guard let apiKey = try? KeychainStore.load(for: .anthropic) else {
                throw LLMError.missingAPIKey(.anthropic)
            }
            return AnthropicProvider(model: action.model, apiKey: apiKey, temperature: action.temperature,
                                     maxTokens: action.maxTokens)

        } else if provider == .gemini {
            guard let apiKey = try? KeychainStore.load(for: .gemini) else {
                throw LLMError.missingAPIKey(.gemini)
            }
            let chatURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
            return OpenAIProvider(model: action.model, apiKey: apiKey, chatURL: chatURL,
                                  authStyle: .bearer, temperature: action.temperature,
                                  maxTokens: action.maxTokens, tokenParamStyle: .maxTokens)

        } else if provider == .grok {
            guard let apiKey = try? KeychainStore.load(for: .grok) else {
                throw LLMError.missingAPIKey(.grok)
            }
            let chatURL = URL(string: "https://api.x.ai/v1/chat/completions")!
            return OpenAIProvider(model: action.model, apiKey: apiKey, chatURL: chatURL,
                                  authStyle: .bearer, temperature: action.temperature,
                                  maxTokens: action.maxTokens, tokenParamStyle: .maxTokens)

        } else if provider.isCustom {
            guard let cp = provider.customProvider else {
                throw LLMError.missingAPIKey(provider)
            }
            guard !cp.baseURL.isEmpty else {
                throw LLMError.missingAPIKey(provider)
            }
            let apiKey = (try? KeychainStore.load(for: provider)) ?? ""
            let chatURL = try customChatURL(baseURLStr: cp.baseURL, apiVersion: cp.apiVersion, provider: provider)
            return OpenAIProvider(model: action.model, apiKey: apiKey, chatURL: chatURL,
                                  authStyle: .bearer, temperature: action.temperature,
                                  maxTokens: action.maxTokens, tokenParamStyle: cp.tokenParamStyle,
                                  extraHeaders: cp.customHeaders)
        }

        throw LLMError.missingAPIKey(provider)
    }

    private static func customChatURL(baseURLStr: String, apiVersion: String?, provider: ProviderType) throws -> URL {
        var base = baseURLStr.hasSuffix("/") ? String(baseURLStr.dropLast()) : baseURLStr
        if !base.hasSuffix("/chat/completions") {
            base += "/chat/completions"
        }
        if let version = apiVersion, !version.isEmpty {
            var components = URLComponents(string: base)
            components?.queryItems = [URLQueryItem(name: "api-version", value: version)]
            guard let url = components?.url else { throw LLMError.missingAPIKey(provider) }
            return url
        }
        guard let url = URL(string: base) else { throw LLMError.missingAPIKey(provider) }
        return url
    }

    private static func azureChatURL(deploymentBase: String, legacyDeployment: String?, apiVersion: String) throws -> URL {
        var base = deploymentBase.hasSuffix("/") ? String(deploymentBase.dropLast()) : deploymentBase

        if base.hasSuffix("/chat/completions") {
            base = String(base.dropLast("/chat/completions".count))
        }

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
