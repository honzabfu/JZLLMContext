import AppKit
import Carbon

final class HotkeyManager: @unchecked Sendable {
    private let callback: @Sendable () -> Void
    private var eventHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(callback: @escaping @Sendable () -> Void) {
        self.callback = callback
    }

    func register() {
        let config = ConfigStore.shared
        let keyCode = UInt32(config.hotkeyKeyCode)
        let modifiers = UInt32(config.hotkeyModifiers)

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x4A5A4C43) // 'JZLC'
        hotKeyID.id = 1

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.callback() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &eventHotKeyRef)
    }

    func reregister() { unregister(); register() }

    func unregister() {
        if let ref = eventHotKeyRef {
            UnregisterEventHotKey(ref)
            eventHotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
    }
}
