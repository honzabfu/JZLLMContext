import Foundation

struct FetchedModel: Identifiable {
    var id: String
    var displayName: String
    var isIncluded: Bool
    var isRecommended: Bool
    var inUseByAction: Bool
}

enum ModelFetchError: LocalizedError {
    case missingAPIKey
    case missingBaseURL
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:    "Chybí API klíč pro daného providera"
        case .missingBaseURL:   "Není zadána Base URL pro vlastního providera"
        case .invalidResponse:  "Neplatná odpověď ze serveru"
        }
    }
}

enum ModelFetcher {
    private static let recommendedIDs: [ProviderType: String] = [
        .openai:    "gpt-5.5",
        .anthropic: "claude-sonnet-4-6",
        .gemini:    "gemini-3.1-pro",
        .grok:      "grok-4.20"
    ]

    static func fetch(for provider: ProviderType) async throws -> [FetchedModel] {
        if provider == .openai {
            return try await fetchOpenAI()
        } else if provider == .anthropic {
            return try await fetchAnthropic()
        } else if provider == .gemini {
            return try await fetchGemini()
        } else if provider == .grok {
            return try await fetchGrok()
        } else if provider.isCustom {
            guard let cp = provider.customProvider else { throw ModelFetchError.missingBaseURL }
            return try await fetchCustomOpenAI(provider: provider, config: cp)
        } else {
            throw ModelFetchError.invalidResponse
        }
    }

    private static func inUseIDs(for provider: ProviderType) -> Set<String> {
        Set(ConfigStore.shared.config.actions
            .filter { $0.provider == provider }
            .map(\.model))
    }

    // MARK: - OpenAI

    private static func fetchOpenAI() async throws -> [FetchedModel] {
        guard let key = try? KeychainStore.load(for: .openai), !key.isEmpty else {
            throw ModelFetchError.missingAPIKey
        }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelFetchError.invalidResponse
        }

        struct Response: Decodable {
            struct Model: Decodable { let id: String; let created: Int? }
            let data: [Model]
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ModelFetchError.invalidResponse
        }

        let excluded = ["embedding", "tts", "whisper", "dall-e", "babbage", "davinci",
                        "ada", "curie", "instruct", "realtime", "audio", "transcribe",
                        "moderation", "search", "similarity", "text-"]
        let inUse = inUseIDs(for: .openai)
        let recommended = recommendedIDs[.openai]

        var models = decoded.data
            .filter { m in !excluded.contains(where: { m.id.lowercased().contains($0) }) }
            .sorted { ($0.created ?? 0) > ($1.created ?? 0) }
            .map { m in
                FetchedModel(id: m.id, displayName: m.id, isIncluded: true,
                             isRecommended: m.id == recommended, inUseByAction: inUse.contains(m.id))
            }

        appendMissingInUse(inUse, recommended: recommended, into: &models)
        return models
    }

    // MARK: - Anthropic

    private static func fetchAnthropic() async throws -> [FetchedModel] {
        guard let key = try? KeychainStore.load(for: .anthropic), !key.isEmpty else {
            throw ModelFetchError.missingAPIKey
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelFetchError.invalidResponse
        }

        struct Response: Decodable {
            struct Model: Decodable { let id: String; let display_name: String? }
            let data: [Model]
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ModelFetchError.invalidResponse
        }

        let inUse = inUseIDs(for: .anthropic)
        let recommended = recommendedIDs[.anthropic]

        var models = decoded.data.map { m in
            FetchedModel(id: m.id, displayName: m.display_name ?? m.id, isIncluded: true,
                         isRecommended: m.id == recommended, inUseByAction: inUse.contains(m.id))
        }

        appendMissingInUse(inUse, recommended: recommended, into: &models)
        return models
    }

    // MARK: - Gemini

    private static func fetchGemini() async throws -> [FetchedModel] {
        guard let key = try? KeychainStore.load(for: .gemini), !key.isEmpty else {
            throw ModelFetchError.missingAPIKey
        }
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/models")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelFetchError.invalidResponse
        }

        struct Response: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ModelFetchError.invalidResponse
        }

        let inUse = inUseIDs(for: .gemini)
        let recommended = recommendedIDs[.gemini]

        var models = decoded.data.map { m in
            FetchedModel(id: m.id, displayName: m.id, isIncluded: true,
                         isRecommended: m.id == recommended, inUseByAction: inUse.contains(m.id))
        }
        appendMissingInUse(inUse, recommended: recommended, into: &models)
        return models
    }

    // MARK: - Grok

    private static func fetchGrok() async throws -> [FetchedModel] {
        guard let key = try? KeychainStore.load(for: .grok), !key.isEmpty else {
            throw ModelFetchError.missingAPIKey
        }
        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/models")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelFetchError.invalidResponse
        }

        struct Response: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ModelFetchError.invalidResponse
        }

        let inUse = inUseIDs(for: .grok)
        let recommended = recommendedIDs[.grok]

        var models = decoded.data.map { m in
            FetchedModel(id: m.id, displayName: m.id, isIncluded: true,
                         isRecommended: m.id == recommended, inUseByAction: inUse.contains(m.id))
        }
        appendMissingInUse(inUse, recommended: recommended, into: &models)
        return models
    }

    // MARK: - Custom OpenAI-compatible

    private static func fetchCustomOpenAI(provider: ProviderType, config cp: CustomProvider) async throws -> [FetchedModel] {
        guard !cp.baseURL.isEmpty else { throw ModelFetchError.missingBaseURL }
        let base = cp.baseURL.hasSuffix("/") ? String(cp.baseURL.dropLast()) : cp.baseURL
        guard let url = URL(string: "\(base)/models") else {
            throw ModelFetchError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if let key = try? KeychainStore.load(for: provider), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        for (k, v) in cp.customHeaders { request.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ModelFetchError.invalidResponse
        }

        struct Response: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ModelFetchError.invalidResponse
        }

        let inUse = inUseIDs(for: provider)
        var models = decoded.data.map { m in
            FetchedModel(id: m.id, displayName: m.id, isIncluded: true,
                         isRecommended: false, inUseByAction: inUse.contains(m.id))
        }
        appendMissingInUse(inUse, recommended: nil, into: &models)
        return models
    }

    // MARK: - Helpers

    private static func appendMissingInUse(
        _ inUse: Set<String>, recommended: String?, into models: inout [FetchedModel]
    ) {
        let fetched = Set(models.map(\.id))
        for id in inUse where !fetched.contains(id) {
            models.append(FetchedModel(id: id, displayName: id, isIncluded: true,
                                       isRecommended: id == recommended, inUseByAction: true))
        }
    }
}
