import Foundation

@MainActor
final class ActionEngine: ObservableObject {
    @Published var result: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var lastError: Error?
    /// Non-fatal problem shown alongside a partial result (e.g. token limit reached).
    @Published var warningMessage: String?
    /// Changes only when a run finishes successfully — never on cancel or error.
    @Published private(set) var completedRunID: UUID?

    private var currentTask: Task<Void, Never>?
    private var activeRunID: UUID?

    func run(action: Action, input: String) {
        cancel()
        isLoading = true
        errorMessage = nil
        lastError = nil
        warningMessage = nil
        result = ""
        let runID = UUID()
        activeRunID = runID

        currentTask = Task {
            // A cancelled task can outlive the start of the next run, so every
            // state write must be guarded by the run identity.
            defer {
                if activeRunID == runID { isLoading = false }
            }
            do {
                let provider = try ProviderFactory.make(for: action)
                for try await chunk in provider.stream(systemPrompt: action.systemPrompt, userContent: input) {
                    guard activeRunID == runID else { return }
                    result += chunk
                }
                guard activeRunID == runID else { return }
                completedRunID = runID
                let finalResult = result
                let language = ConfigStore.shared.config.appLanguage
                Task.detached {
                    await HistoryLogger.shared.log(action: action, input: input, response: finalResult, language: language)
                }
            } catch is CancellationError {
                return
            } catch let urlError as URLError where urlError.code == .cancelled {
                return
            } catch LLMError.truncated(let maxTokens) where !result.isEmpty {
                // Keep the partial text but don't treat it as a completed run:
                // no history entry, no auto copy & close
                guard activeRunID == runID else { return }
                warningMessage = LLMError.truncated(maxTokens: maxTokens).localizedDescription
            } catch LLMError.truncated(let maxTokens) {
                // No text at all: a reasoning model spent the whole limit on thinking
                guard activeRunID == runID else { return }
                lastError = LLMError.truncated(maxTokens: maxTokens)
                errorMessage = String(format: L("error.truncated_empty"), maxTokens)
            } catch {
                guard activeRunID == runID else { return }
                lastError = error
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        activeRunID = nil
        isLoading = false
    }

    func reset() {
        cancel()
        result = ""
        errorMessage = nil
        lastError = nil
        warningMessage = nil
        completedRunID = nil
    }

    func showText(_ text: String) {
        cancel()
        result = text
        errorMessage = nil
        warningMessage = nil
    }
}
