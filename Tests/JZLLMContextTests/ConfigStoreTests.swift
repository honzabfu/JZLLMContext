import Foundation
import Testing
@testable import JZLLMContext

struct ConfigStoreTests {
    private func fixture(_ values: [String: Any] = [:]) throws -> Data {
        var json: [String: Any] = [
            "schemaVersion": 4, "hotkeyKeyCode": 49, "hotkeyModifiers": 768, "actions": []
        ]
        json.merge(values) { _, new in new }
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func withTemporaryConfig(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("config.json"))
    }

    @Test(arguments: ["hotkeyKeyCode", "hotkeyModifiers"])
    func rejectsInvalidHotkeys(field: String) throws {
        for value in [-1, Int(UInt32.max) + 1, Int.max] {
            let data = try fixture([field: value])
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(AppConfig.self, from: data) }
        }
        for value in [0, Int(UInt32.max)] {
            let config = try JSONDecoder().decode(AppConfig.self, from: fixture([field: value]))
            #expect(UInt32(exactly: config.hotkeyKeyCode) != nil)
            #expect(UInt32(exactly: config.hotkeyModifiers) != nil)
        }
    }

    @Test func validatesHistoryBounds() throws {
        for value in [-1, 11, Int.min, Int.max] {
            let data = try fixture(["historyLimit": value])
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(AppConfig.self, from: data) }
        }
        for value in [0, 10] {
            let config = try JSONDecoder().decode(AppConfig.self, from: fixture(["historyLimit": value]))
            #expect(config.historyLimit == value)
        }
    }

    @Test func unknownCopyModePreservesAction() throws {
        let id = UUID()
        let data = try fixture(["actions": [[
            "id": id.uuidString, "name": "Keep me", "systemPrompt": "s", "provider": "openai",
            "model": "m", "enabled": true, "autoCopyClose": "future-mode"
        ]]])
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(config.actions.count == 1)
        #expect(config.actions.first?.id == id)
        #expect(config.actions.first?.autoCopyClose == .useGlobal)
    }

    @Test func invalidFilesAreBackedUpBeforeSavingDefaults() throws {
        try withTemporaryConfig { url in
            let inputs = [Data("{broken".utf8), try fixture(["hotkeyKeyCode": -1])]
            for input in inputs {
                try input.write(to: url)
                let store = ConfigStore(fileURL: url)
                #expect(store.config.hotkeyKeyCode == AppConfig.default.hotkeyKeyCode)
                try store.save()
                _ = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: url))
            }
            let backups = try FileManager.default.contentsOfDirectory(
                at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasPrefix("config.json.corrupt.") }
            #expect(backups.count == 2)
            let contents = try backups.map { try Data(contentsOf: $0) }
            for input in inputs { #expect(contents.contains(input)) }
        }
    }

    @Test func migrationsArePersistedImmediatelyAndRemainStable() throws {
        try withTemporaryConfig { url in
            // Schema 2 avoids legacy Keychain migration, keeping this test isolated.
            let provider = CustomProvider(name: "Local", baseURL: "http://localhost:1234")
            var old = AppConfig.default
            old.schemaVersion = 2
            old.customProviders = [provider]
            old.actions = [Action(name: "Keep", systemPrompt: "s", provider: ProviderType(provider.id.uuidString),
                                  model: "local", enabled: true, maxTokens: 2048)]
            try JSONEncoder().encode(old).write(to: url)
            let first = ConfigStore(fileURL: url)
            let saved = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: url))
            let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            #expect(json["schemaVersion"] as? Int == 4)
            #expect(saved.actions.first?.maxTokens == Action.defaultMaxTokens)
            let second = ConfigStore(fileURL: url)
            #expect(second.config.customProviders.first?.id == first.config.customProviders.first?.id)
            #expect(second.config.actions.first?.provider == ProviderType(provider.id.uuidString))
        }
    }

    @Test func currentConfigIsNotRewrittenOnLoad() throws {
        try withTemporaryConfig { url in
            let data = try fixture()
            try data.write(to: url)
            _ = ConfigStore(fileURL: url)
            #expect(try Data(contentsOf: url) == data)
        }
    }

    @Test @MainActor func negativeHistoryTrimDoesNotTrap() {
        HistoryStore.shared.trim(to: -1)
        #expect(HistoryStore.shared.entries.isEmpty)
    }
}
