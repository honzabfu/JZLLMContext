# JZLLMContext – developer documentation

Moved out of the README so that it stays focused on users. Czech version: [DEVELOPMENT.cs.md](DEVELOPMENT.cs.md). Rules for coding agents: [`CLAUDE.md`](../CLAUDE.md).

## Building from Source

```bash
# Clone the repository
git clone https://github.com/honzabfu/JZLLMContext.git
cd JZLLMContext

# Generate the Xcode project
brew install xcodegen
xcodegen generate

# Build the app
xcodebuild -scheme JZLLMContext -configuration Debug build

# Run the unit tests (network is mocked — no API keys or costs)
xcodebuild test -scheme JZLLMContext -destination 'platform=macOS'

# Optional: live tests against the real provider APIs, using the API keys and
# provider settings stored by the app (costs a few cents)
TEST_RUNNER_LIVE_API_TESTS=1 xcodebuild test -scheme JZLLMContext -destination 'platform=macOS' \
  -only-testing:JZLLMContextTests/LiveAPITests
```

The built app is located at:

```
~/Library/Developer/Xcode/DerivedData/JZLLMContext-*/Build/Products/Debug/JZLLMContext.app
```

## App Icons

The app looks for these PNG files in the asset catalog. Without them it falls back to a system star symbol.

| File | Size | Usage |
|------|------|-------|
| `Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.png` | 18×18 px, black & white | Menu bar icon (template) |
| `Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png` | 36×36 px, black & white | Menu bar icon @2x |
| `Assets.xcassets/AppColorIcon.imageset/AppColorIcon.png` | min. 64×64 px, color | Icon in the dropdown menu |

## Architecture

```
AppDelegate
  ├── HotkeyManager          – global shortcut registration via Carbon API
  ├── OverlayWindowController – NSPanel management (created once, shown repeatedly)
  │     └── OverlayView       – SwiftUI overlay panel UI
  │           └── ActionEngine – async LLM calls (ObservableObject)
  ├── SettingsWindowController – NSWindow + NSHostingView(SettingsView)
  └── AboutWindowController   – NSWindow + NSHostingView(AboutView)

ConfigStore (singleton)       – read/write config.json
KeychainStore                 – store API keys in macOS Keychain
ContextResolver               – read NSPasteboard + Vision OCR
ProviderFactory               – create LLMProvider based on action config
  ├── OpenAIProvider           – OpenAI + Azure OpenAI (2 slots) + dynamic custom endpoints
  └── AnthropicProvider        – Anthropic Claude
```

The overlay panel is created once and reused. Subsequent shortcut presses refresh the clipboard unless a dropped file is loaded; in that case the file, current run and result are preserved.

The app is an LSUIElement (agent) – no Dock icon and no standard app menu bar, so the settings window is managed manually via `NSWindowController` in `AppDelegate`.

## OCR Pipeline

When the overlay panel is activated, the app checks the clipboard:

1. A file copied in Finder is read first; for an image, its text is recognized instead of using its filename
2. Otherwise, copied text is used directly
3. Otherwise, text is recognized from a copied image. Recognition runs in the background; if it fails or finds no text, an error is shown
4. If the clipboard is empty → an error message is shown

## Global Shortcut

The shortcut is registered via Carbon `RegisterEventHotKey` with identifier `JZLC`. On change, `unregister()` is called followed by `register()` with the new values; the change is propagated via `NotificationCenter` (`hotkeyDidChange`).

---
