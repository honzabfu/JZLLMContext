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

## File processing

Files enter via two paths — both call `ContextResolver.extractText(from:)`:

1. **Drag & drop** — `OverlayView.handleDroppedFile(url:)` via `.onDrop(of: [UTType.fileURL])` + `NSItemProvider.loadObject(ofClass: URL.self)`
2. **Clipboard** — `ContextResolver.resolve()` detects a file URL via `NSPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])`; non-image files are routed through `extractText`, image files fall through to `NSImage(pasteboard:)` → OCR.

`PDFKit.framework` is linked in `project.yml` (under target dependencies). Spotlight extraction (`MDItemCreateWithURL`) runs on `DispatchQueue.global` wrapped in `withCheckedContinuation`; plain-text reads use `Task.detached`. Two race-condition guards in `OverlayView` must be kept after every `await` that updates view state: `guard droppedFileURL == url else { return }` in `handleDroppedFile`, and `guard !Task.isCancelled else { return }` in `resolveContext()` (which stores its task in `resolveTask` and cancels the superseded one — `handleDroppedFile` cancels it too).
