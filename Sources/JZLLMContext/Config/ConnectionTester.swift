import Foundation

enum ConnectionTester {
    static func test(for provider: ProviderType) async throws {
        switch provider {
        case .openai:       try await pingOpenAI()
        case .anthropic:    try await pingAnthropic()
        case .azureOpenai:  try await pingAzure(slot: 1)
        case .azureOpenai2: try await pingAzure(slot: 2)
        case .customOpenAI: try await pingCustom()
        }
    }

    // MARK: - OpenAI

    private static func pingOpenAI() async throws {
        guard let key = try? KeychainStore.load(for: .openai), !key.isEmpty else {
            throw LLMError.missingAPIKey(.openai)
        }
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(data: data, response: response)
    }

    // MARK: - Anthropic

    private static func pingAnthropic() async throws {
        guard let key = try? KeychainStore.load(for: .anthropic), !key.isEmpty else {
            throw LLMError.missingAPIKey(.anthropic)
        }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(data: data, response: response)
    }

    // MARK: - Azure

    private static func pingAzure(slot: Int) async throws {
        let providerType: ProviderType = slot == 1 ? .azureOpenai : .azureOpenai2
        guard let key = try? KeychainStore.load(for: providerType), !key.isEmpty else {
            throw LLMError.missingAPIKey(providerType)
        }
        let config = ConfigStore.shared.config
        let endpointStr = slot == 1 ? config.azureEndpoint : config.azureEndpoint2
        let deploymentName = slot == 1 ? config.azureDeploymentName : config.azureDeploymentName2
        let apiVersion = (slot == 1 ? config.azureAPIVersion : config.azureAPIVersion2) ?? AppConfig.defaultAzureAPIVersion

        guard let endpointStr, !endpointStr.isEmpty else {
            throw LLMError.missingAPIKey(providerType)
        }
        let chatURL = try azureChatURL(deploymentBase: endpointStr, legacyDeployment: deploymentName, apiVersion: apiVersion)
        try await pingChatCompletions(url: chatURL, apiKey: key, authStyle: .apiKey)
    }

    // MARK: - Custom OpenAI-compatible

    private static func pingCustom() async throws {
        let key = (try? KeychainStore.load(for: .customOpenAI)) ?? ""
        let config = ConfigStore.shared.config
        guard let urlStr = config.customOpenAIBaseURL, !urlStr.isEmpty,
              let baseURL = URL(string: urlStr) else {
            throw LLMError.missingAPIKey(.customOpenAI)
        }
        var req = URLRequest(url: baseURL.appendingPathComponent("models"))
        if !key.isEmpty { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        req.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(data: data, response: response)
    }

    // MARK: - Helpers

    private static func pingChatCompletions(url: URL, apiKey: String, authStyle: OpenAIAuthStyle) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        switch authStyle {
        case .bearer: req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .apiKey: req.setValue(apiKey, forHTTPHeaderField: "api-key")
        }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15

        struct MinimalRequest: Encodable {
            let messages: [Msg]
            let max_tokens: Int
            struct Msg: Encodable { let role: String; let content: String }
        }
        req.httpBody = try? JSONEncoder().encode(
            MinimalRequest(messages: [.init(role: "user", content: "Hi")], max_tokens: 1)
        )

        let (data, response) = try await URLSession.shared.data(for: req)
        try validate(data: data, response: response)
    }

    private static func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw LLMError.decodingError }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.httpError(http.statusCode, message)
        }
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
