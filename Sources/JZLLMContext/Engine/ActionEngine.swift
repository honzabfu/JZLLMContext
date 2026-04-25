import Foundation

enum ActionEngineError: Error, LocalizedError {
    case providerError(Error)

    var errorDescription: String? {
        switch self {
        case .providerError(let error): error.localizedDescription
        }
    }
}

@MainActor
final class ActionEngine: ObservableObject {
    @Published var result: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private var currentTask: Task<Void, Never>?

    func run(action: Action, input: String) {
        cancel()
        isLoading = true
        errorMessage = nil
        result = ""

        currentTask = Task {
            do {
                let provider = try ProviderFactory.make(for: action)
                let output = try await provider.complete(systemPrompt: action.systemPrompt, userContent: input)
                result = output
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
    }

    func reset() {
        cancel()
        result = ""
        errorMessage = nil
    }

    func showText(_ text: String) {
        cancel()
        result = text
        errorMessage = nil
    }
}
