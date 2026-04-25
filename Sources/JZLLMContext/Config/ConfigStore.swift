import Carbon
import Foundation

final class ConfigStore: @unchecked Sendable {
    static let shared = ConfigStore()

    private let fileURL: URL
    private(set) var config: AppConfig

    var hotkeyKeyCode: Int { config.hotkeyKeyCode }
    var hotkeyModifiers: Int { config.hotkeyModifiers }
    var actions: [Action] { config.actions }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("JZLLMContext", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")
        config = (try? ConfigStore.load(from: fileURL)) ?? AppConfig.default
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }

    func update(_ block: (inout AppConfig) -> Void) {
        block(&config)
        try? save()
    }

    private static func load(from url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }
}
