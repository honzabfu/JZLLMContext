# JZLLMContext

macOS menu bar app (Swift 6, macOS 15+). Architecture and full feature overview in README.md.

## Build

```bash
xcodegen generate   # must run first — regenerates the .xcodeproj from project.yml
xcodebuild -scheme JZLLMContext -configuration Debug build
```

Use `/rebuild` to build and relaunch the app, `/release` to publish a new GitHub release.

## Swift 6 strict concurrency

All code compiles with `SWIFT_STRICT_CONCURRENCY: complete`. Every change must satisfy the compiler — no `@unchecked Sendable` shortcuts without a clear reason.

## Config & state sync

`ConfigStore` is the single source of truth; every mutation must go through `ConfigStore.update`, which persists and posts `Notification.Name.configDidChange`. `SettingsView` holds only a `@State` snapshot of the config and re-reads it on that notification (deferred via `.receive(on: DispatchQueue.main)` to avoid re-entrant updates from its own `onChange` handlers) — never persist the snapshot without going through `update`.

`exportConfig()` in `SettingsView` blanks custom-provider header values before encoding; any new secret-bearing config field must be sanitized there too (API keys themselves live in Keychain, not in config).

## Providers

`OpenAIProvider` omits the `temperature` parameter for o-series reasoning models (model id matching `^o\d`) — they reject non-default values with HTTP 400. Azure error paths take the concrete `ProviderType` (slot 1 vs slot 2) so messages point at the right slot.

## UI conventions (overlay)

Use `UICornerRadius.small` (4) / `.large` (8) for corner radii instead of magic numbers — keeps overlay/settings rounding consistent.

`OverlayWindowController` hides the standard traffic-light window buttons (`standardWindowButton(.closeButton/.miniaturizeButton/.zoomButton)?.isHidden = true`); `OverlayView` provides its own ✕ in the header, so don't re-enable the system buttons.

The context `TextField` (`userContextFocused`) must keep keyboard focus so `.onKeyPress(.return, ...)` triggers the default action — `.defaultFocus($userContextFocused, true)` plus explicit `userContextFocused = true` in both `.onAppear` and `.onChange(of: state.refreshID)` (the panel is created once and reused, so `.onAppear` only fires on the very first show). Icon-only header buttons use `iconButton()` (`.buttonStyle(.plain).focusEffectDisabled()`) so they don't steal this focus or break digit shortcuts.

The result area is `.focusable()`/`.focused($resultAreaFocused)` so users can text-select within it; while it has focus, the **Copy** button's Cmd+C shortcut is rebound to an unused key equivalent (an empty modifier set does not disable a SwiftUI `.keyboardShortcut`) so Cmd+C falls through to normal text-selection copy.

`testConnectionRow` saves the API key field to Keychain before testing — otherwise "Test connection" would verify the stale stored key after an unsaved edit.

## File processing

Files enter via two paths — both call `ContextResolver.extractText(from:)`:

1. **Drag & drop** — `OverlayView.handleDroppedFile(url:)` via `.onDrop(of: [UTType.fileURL])` + `NSItemProvider.loadObject(ofClass: URL.self)`
2. **Clipboard** — `ContextResolver.resolve()` detects a file URL via `NSPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])`; non-image files are routed through `extractText`, image files fall through to `NSImage(pasteboard:)` → OCR.

`PDFKit.framework` is linked in `project.yml` (under target dependencies). Spotlight extraction (`MDItemCreateWithURL`) runs on `DispatchQueue.global` wrapped in `withCheckedContinuation`; plain-text reads use `Task.detached`. Two race-condition guards in `OverlayView` must be kept after every `await` that updates view state: `guard droppedFileURL == url else { return }` in `handleDroppedFile`, and `guard !Task.isCancelled else { return }` in `resolveContext()` (which stores its task in `resolveTask` and cancels the superseded one — `handleDroppedFile` cancels it too).
