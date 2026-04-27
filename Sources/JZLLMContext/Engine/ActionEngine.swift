import Foundation

@MainActor
final class ActionEngine: ObservableObject {
    @Published var result: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var lastError: Error?

    private var currentTask: Task<Void, Never>?

    func run(action: Action, input: String) {
        cancel()
        isLoading = true
        errorMessage = nil
        result = ""

        currentTask = Task {
            defer { isLoading = false }
            do {
                let provider = try ProviderFactory.make(for: action)
                for try await chunk in provider.stream(systemPrompt: action.systemPrompt, userContent: input) {
                    result += chunk
                }
            } catch is CancellationError {
                return
            } catch let urlError as URLError where urlError.code == .cancelled {
                return
            } catch {
                lastError = error
                errorMessage = error.localizedDescription
            }
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
        lastError = nil
    }

    func showText(_ text: String) {
        cancel()
        result = text
        errorMessage = nil
    }
}
