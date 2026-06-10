import Carbon
import Foundation
import Synchronization

final class ConfigStore: Sendable {
    static let shared = ConfigStore()

    private let fileURL: URL
    // Guards config against cross-thread access (HistoryLogger actor, detached tasks)
    private let state: Mutex<AppConfig>

    var config: AppConfig { state.withLock { $0 } }
    var hotkeyKeyCode: Int { config.hotkeyKeyCode }
    var hotkeyModifiers: Int { config.hotkeyModifiers }
    var actions: [Action] { config.actions }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("JZLLMContext", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")
        state = Mutex((try? ConfigStore.load(from: fileURL)) ?? AppConfig.default)
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }

    func update(_ block: (inout AppConfig) -> Void) {
        state.withLock { block(&$0) }
        try? save()
    }

    func reset() {
        state.withLock { $0 = AppConfig.makeDefault(language: $0.appLanguage) }
        try? FileManager.default.removeItem(at: fileURL)
        try? save()
    }

    private static func load(from url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }
}
