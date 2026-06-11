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
    /// Set once the user resizes the panel by hand; from then on the
    /// automatic height management backs off and their size wins.
    private var userResizedPanel = false

    func showOverlay() {
        if panel == nil {
            panel = makePanel()
            panel?.center()
        }
        state.triggerRefresh()
        if !userResizedPanel {
            adjustPanelHeight()
        }
        panel?.makeKeyAndOrderFront(nil)
    }

    private func adjustPanelHeight() {
        let actionCount = ConfigStore.shared.actions.filter(\.enabled).count
        let targetHeight = CGFloat(min(max(160 + actionCount * 44, 280), 620))
        setPanelHeight(targetHeight, animate: false)
    }

    /// Grows the panel when a result arrives so the result area gets
    /// usable space instead of squeezing under the action list.
    private func expandForResult() {
        guard !userResizedPanel, let panel else { return }
        let maxHeight = ((panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 800) - 40
        let target = min(max(panel.frame.height, 560), maxHeight)
        if target > panel.frame.height {
            setPanelHeight(target, animate: true)
        }
    }

    /// Resizes the panel keeping its top edge in place, clamped to the screen.
    private func setPanelHeight(_ targetHeight: CGFloat, animate: Bool) {
        guard let panel = panel, panel.frame.height != targetHeight else { return }
        let currentFrame = panel.frame
        let newY = currentFrame.maxY - targetHeight
        let clampedY: CGFloat
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            clampedY = max(visible.minY, min(newY, visible.maxY - targetHeight))
        } else {
            clampedY = newY
        }
        panel.setFrame(NSRect(x: currentFrame.minX, y: clampedY, width: currentFrame.width, height: targetHeight),
                       display: true, animate: animate)
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
        // OverlayView provides its own ✕ close button in the header bar.
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let overlayView = OverlayView(state: state, onClose: { [weak self] in
            self?.hideOverlay()
        }, onOpenSettings: { [weak self] in
            self?.hideOverlay()
            self?.onOpenSettings?()
        }, onResultAppeared: { [weak self] in
            self?.expandForResult()
        })
        panel.contentView = NSHostingView(rootView: overlayView)
        panel.delegate = self
        return panel
    }
}

extension OverlayWindowController: NSWindowDelegate {
    // Fires only for user-driven drag resizing, not for programmatic
    // setFrame calls — exactly the signal that the user picked a size.
    func windowDidEndLiveResize(_ notification: Notification) {
        userResizedPanel = true
    }
}
