import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: HotkeyManager?
    private var overlayWindowController: OverlayWindowController?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var hotkeyState = HotkeyState.shared
    private var updateMenuItem: NSMenuItem?
    private var updateURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBarItem()
        hotkeyManager = HotkeyManager { [weak self] in
            Task { @MainActor in self?.showOverlay() }
        }
        hotkeyManager?.register()
        NotificationCenter.default.addObserver(
            forName: .hotkeyDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            self?.hotkeyManager?.reregister()
        }
        NotificationCenter.default.addObserver(
            forName: .updateAvailable, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let version = notification.userInfo?["version"] as? String,
                  let url = notification.userInfo?["url"] as? URL else { return }
            self.showUpdateMenuItem(version: version, url: url)
        }
        Task { await UpdateChecker.checkOnLaunch() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregister()
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            if let icon = NSImage(named: "MenuBarIcon") {
                icon.isTemplate = true
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "JZLLMContext")
            }
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let menu = NSMenu()

        let headerItem = NSMenuItem()
        let headerView = NSHostingView(rootView: MenuHeaderView(hotkeyState: hotkeyState))
        headerView.frame = NSRect(x: 0, y: 0, width: 240, height: 54)
        headerItem.view = headerView
        menu.addItem(headerItem)
        menu.addItem(.separator())

        let updateItem = NSMenuItem(title: "", action: #selector(openUpdateURL), keyEquivalent: "")
        updateItem.target = self
        updateItem.isHidden = true
        menu.addItem(updateItem)
        updateMenuItem = updateItem

        let aboutItem = NSMenuItem(title: "O aplikaci JZLLMContext", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let settingsItem = NSMenuItem(title: "Nastavení…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Ukončit JZLLMContext", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusMenu = menu
    }

    private func showUpdateMenuItem(version: String, url: URL) {
        updateURL = url
        updateMenuItem?.title = "⬆ Dostupná verze \(version)…"
        updateMenuItem?.isHidden = false
    }

    @objc private func openUpdateURL() {
        guard let url = updateURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.option) {
            statusItem?.menu = statusMenu
            sender.performClick(nil)
            statusItem?.menu = nil
        } else {
            showOverlay()
        }
    }

    @objc private func openAbout() {
        if aboutWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 580),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "O aplikaci"
            window.isRestorable = false
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.contentViewController = NSHostingController(rootView: AboutView())
            window.center()
            aboutWindow = window
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.aboutWindow = nil }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        overlayWindowController?.hideOverlay()
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "JZLLMContext"
            window.isRestorable = false
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 620, height: 520)
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.center()
            settingsWindow = window
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.settingsWindow = nil }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @MainActor
    func showOverlay() {
        if overlayWindowController == nil {
            let controller = OverlayWindowController()
            controller.onOpenSettings = { [weak self] in self?.openSettings() }
            overlayWindowController = controller
        }
        overlayWindowController?.showOverlay()
    }
}

private struct MenuHeaderView: View {
    @ObservedObject var hotkeyState: HotkeyState

    var body: some View {
        HStack(spacing: 10) {
            if let icon = NSImage(named: "AppColorIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("JZLLMContext").font(.headline)
                Text(hotkeyState.displayString).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
