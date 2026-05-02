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
    var onOpenSettings: (() -> Void)?

    func showOverlay() {
        if panel == nil {
            panel = makePanel()
            panel?.center()
        }
        state.triggerRefresh()
        adjustPanelHeight()
        panel?.makeKeyAndOrderFront(nil)
    }

    private func adjustPanelHeight() {
        let actionCount = ConfigStore.shared.actions.filter(\.enabled).count
        let targetHeight = CGFloat(min(max(160 + actionCount * 44, 280), 620))
        guard let panel = panel, panel.frame.height != targetHeight else { return }
        let currentFrame = panel.frame
        let newY = currentFrame.maxY - targetHeight
        let clampedY: CGFloat
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            clampedY = max(visible.minY, min(newY, visible.maxY - targetHeight))
        } else {
            clampedY = newY
        }
        panel.setFrame(NSRect(x: currentFrame.minX, y: clampedY, width: currentFrame.width, height: targetHeight), display: true)
    }

    func hideOverlay() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isRestorable = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let overlayView = OverlayView(state: state, onClose: { [weak self] in
            self?.hideOverlay()
        }, onOpenSettings: { [weak self] in
            self?.hideOverlay()
            self?.onOpenSettings?()
        })
        panel.contentView = NSHostingView(rootView: overlayView)
        return panel
    }
}
