# Release Notes

## Unreleased

## v0.58 – 2026-05-02
- Fix: warning triangle no longer shown for custom OpenAI-compatible providers (local models do not require an API key)
- History panel: "Open log folder" button added at the bottom — visible when interaction logging is enabled
- Custom OpenAI-compatible providers now support "Update Models" to fetch the available model list from the server's `/models` endpoint (works with Ollama, LM Studio, and other OpenAI-compatible servers)

## v0.57 – 2026-05-02
- Update indicator: when a new version is detected automatically, an info icon (ⓘ) appears in the overlay header bar next to the version number; clicking it opens the GitHub release page directly

## v0.56 – 2026-05-02
- Opt-in interaction logging: each completed action can be appended to a dated Markdown file in a user-defined directory; configurable file name prefix; sensitive-data warning shown on first enable
- Clipboard change indicator: a refresh icon appears below the eye button when the clipboard content changes while the panel is open; clicking it reloads the content
- Sensitive content detection: clipboard text is scanned against built-in and custom regex patterns (API keys, tokens, private keys) before sending to the LLM; a confirmation sheet lists matches and requires explicit approval
- Fix: update checker now only notifies when a genuinely newer version is available (was triggering on any version that differed from the running one)

## v0.55 – 2026-04-30
- Localized custom API section names in Settings

## v0.54 – 2026-04-30
- Added Google Gemini and xAI Grok providers

## v0.53 – 2026-04-30
- Added localization support (Czech, English, Spanish UI)

## v0.52 – 2026-04-30
- Update notification now appears as a menu item instead of a system notification
