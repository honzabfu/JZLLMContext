import AppKit
import SwiftUI

@MainActor
final class OverlayState: ObservableObject {
    @Published var refreshID = UUID()

    func triggerRefresh() {
        refreshID = UUID()
    }
}

@MainActor
final class OverlayWindowController: NSObject {
    private var panel: NSPanel?
    private let state = OverlayState()

    func showOverlay() {
        if panel == nil {
            panel = makePanel()
        }
        state.triggerRefresh()
        panel?.makeKeyAndOrderFront(nil)
        panel?.center()
    }

    func hideOverlay() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isRestorable = false
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let overlayView = OverlayView(state: state, onClose: { [weak self] in
            self?.hideOverlay()
        })
        panel.contentView = NSHostingView(rootView: overlayView)
        return panel
    }
}
