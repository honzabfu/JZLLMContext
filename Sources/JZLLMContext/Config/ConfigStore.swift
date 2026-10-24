import Carbon
import Foundation
import Synchronization

extension Notification.Name {
    static let configDidChange = Notification.Name("JZLLMContextConfigDidChange")
}

final class ConfigStore: Sendable {
    static let shared = ConfigStore()

    private let fileURL: URL
    // Guards config against cross-thread access (HistoryLogger actor, detached tasks)
    private let state: Mutex<AppConfig>
    private let canPersist: Bool

    var config: AppConfig { state.withLock { $0 } }
    var hotkeyKeyCode: Int { config.hotkeyKeyCode }
    var hotkeyModifiers: Int { config.hotkeyModifiers }
    var actions: [Action] { config.actions }

    private convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("JZLLMContext", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(fileURL: dir.appendingPathComponent("config.json"))
    }

    // An explicit URL keeps persistence tests away from the user's real config.
    init(fileURL: URL) {
        self.fileURL = fileURL
        var loaded = AppConfig.default
        var migrated = false
        var persistenceAllowed = true
        do {
            let data = try Data(contentsOf: fileURL)
            loaded = try JSONDecoder().decode(AppConfig.self, from: data)
            let original = try JSONDecoder().decode(SchemaVersion.self, from: data)
            migrated = original.schemaVersion < loaded.schemaVersion
        } catch {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                // Keep every failed input, including repeated failures, without overwriting
                // an earlier backup. If copying fails, never overwrite the source either.
                let backup = fileURL.appendingPathExtension("corrupt.\(UUID().uuidString)")
                do {
                    try FileManager.default.copyItem(at: fileURL, to: backup)
                } catch {
                    persistenceAllowed = false
                }
            }
        }
        state = Mutex(loaded)
        canPersist = persistenceAllowed
        if migrated { try? save() }
    }

    func save() throws {
        guard canPersist else { throw CocoaError(.fileWriteNoPermission) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }

    func update(_ block: (inout AppConfig) -> Void) {
        state.withLock { block(&$0) }
        try? save()
        NotificationCenter.default.post(name: .configDidChange, object: nil)
    }

    func reset() {
        state.withLock { $0 = AppConfig.makeDefault(language: $0.appLanguage) }
        try? save()
        NotificationCenter.default.post(name: .configDidChange, object: nil)
    }

    private struct SchemaVersion: Decodable {
        let schemaVersion: Int
    }
}
