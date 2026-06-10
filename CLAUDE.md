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

## File processing

Files enter via two paths — both call `ContextResolver.extractText(from:)`:

1. **Drag & drop** — `OverlayView.handleDroppedFile(url:)` via `.onDrop(of: [UTType.fileURL])` + `NSItemProvider.loadObject(ofClass: URL.self)`
2. **Clipboard** — `ContextResolver.resolve()` detects a file URL via `NSPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])`; non-image files are routed through `extractText`, image files fall through to `NSImage(pasteboard:)` → OCR.

`PDFKit.framework` is linked in `project.yml` (under target dependencies). Spotlight extraction (`MDItemCreateWithURL`) runs on `DispatchQueue.global` wrapped in `withCheckedContinuation`; plain-text reads use `Task.detached`. The `handleDroppedFile` race-condition guard (`guard droppedFileURL == url else { return }`) must be kept after every `await` that updates view state.
