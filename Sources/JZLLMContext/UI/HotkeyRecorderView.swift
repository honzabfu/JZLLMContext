import AppKit
import Carbon
import SwiftUI

extension Notification.Name {
    static let hotkeyDidChange = Notification.Name("JZLLMContextHotkeyDidChange")
}

// MARK: - Helpers

func hotkeyDisplayString(keyCode: Int, modifiers: Int) -> String {
    var s = ""
    if modifiers & Int(controlKey) != 0 { s += "⌃" }
    if modifiers & Int(optionKey)  != 0 { s += "⌥" }
    if modifiers & Int(shiftKey)   != 0 { s += "⇧" }
    if modifiers & Int(cmdKey)     != 0 { s += "⌘" }
    s += keyCodeLabel(keyCode)
    return s
}

func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
    var mods = 0
    if flags.contains(.command) { mods |= Int(cmdKey) }
    if flags.contains(.shift)   { mods |= Int(shiftKey) }
    if flags.contains(.option)  { mods |= Int(optionKey) }
    if flags.contains(.control) { mods |= Int(controlKey) }
    return mods
}

private func keyCodeLabel(_ keyCode: Int) -> String {
    let map: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3",
        100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14",
        109: "F10", 111: "F12", 113: "F15", 115: "↖", 116: "⇞",
        117: "⌦", 118: "F4", 119: "↘", 120: "F2", 121: "⇟",
        122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
    return map[keyCode] ?? "?"
}

// MARK: - HotkeyState (shared observable for menu bar display)

@MainActor
final class HotkeyState: ObservableObject {
    static let shared = HotkeyState()
    @Published var displayString: String = ""

    init() {
        refresh()
        NotificationCenter.default.addObserver(
            forName: .hotkeyDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let c = ConfigStore.shared.config
        displayString = hotkeyDisplayString(keyCode: c.hotkeyKeyCode, modifiers: c.hotkeyModifiers)
    }
}

// MARK: - NSViewRepresentable

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: Int

    func makeNSView(context: Context) -> KeyRecorderField {
        let field = KeyRecorderField()
        field.isEditable = false
        field.isSelectable = false
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.alignment = .center
        field.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        field.onRecord = { kc, mods in
            keyCode = kc
            modifiers = mods
        }
        field.stringValue = hotkeyDisplayString(keyCode: keyCode, modifiers: modifiers)
        return field
    }

    func updateNSView(_ field: KeyRecorderField, context: Context) {
        if !field.isRecording {
            field.stringValue = hotkeyDisplayString(keyCode: keyCode, modifiers: modifiers)
        }
    }

    static func dismantleNSView(_ nsView: KeyRecorderField, coordinator: ()) {
        nsView.stopRecording()
    }
}

// MARK: - KeyRecorderField

final class KeyRecorderField: NSTextField, @unchecked Sendable {
    var onRecord: ((Int, Int) -> Void)?
    private(set) var isRecording = false
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        stringValue = "Stiskni zkratku…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = carbonModifiers(from: event.modifierFlags)
            guard mods != 0 else { return nil }
            let kc = Int(event.keyCode)
            DispatchQueue.main.async {
                self.stopRecording()
                self.onRecord?(kc, mods)
            }
            return nil
        }
    }

    func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
