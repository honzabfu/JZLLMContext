import Foundation

struct HistoryEntry: Identifiable {
    let id = UUID()
    let actionName: String
    let inputSnippet: String
    let result: String
    let date: Date
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    @Published private(set) var entries: [HistoryEntry] = []

    private init() {}

    func add(actionName: String, input: String, result: String) {
        let limit = ConfigStore.shared.config.historyLimit
        guard limit > 0 else { return }
        entries.insert(
            HistoryEntry(actionName: actionName, inputSnippet: String(input.prefix(80)), result: result, date: Date()),
            at: 0
        )
        if entries.count > limit { entries = Array(entries.prefix(limit)) }
    }

    func trim(to limit: Int) {
        if entries.count > limit { entries = Array(entries.prefix(limit)) }
    }
}
