# Release Notes

## Unreleased

## v0.65 – 2026-06-11
- Settings: Actions tab redesigned as master–detail — action list on the left, full editor on the right
- Settings: Providers tab restructured — each provider is a collapsible section
- Settings: model filter tags wrap to multiple lines instead of overflowing
- Overlay: panel grows to fit the result; manual window resize is respected and disables automatic sizing
- Overlay: digit shortcuts 1–9 are blocked while an action is running
- Overlay: clipboard change indicator no longer triggers on the app's own clipboard writes (auto-copy)
- Fix: "Ignore clipboard" actions no longer send empty input when there is no manual context
- Fix: history now records the input actually sent (after clipboard-ignore and context embedding)
- Fix: Azure slot 2 connection errors are reported under the correct provider
- Fix: `temperature` is omitted for OpenAI o-series reasoning models (they reject non-default values)
- Fix: invalid custom sensitive patterns are surfaced with a warning in Settings instead of being silently skipped
- Fix: history logger recovers when the log file is deleted while the app is running
- Fix: Settings window picks up edits made elsewhere (e.g. prompt edited via the overlay) instead of overwriting them with stale data
- Security: custom HTTP header values are stripped from configuration export
- Czech localization uses „poskytovatel" consistently instead of "provider"
- README screenshots refreshed (cs + en)

## v0.64 – 2026-06-10
- File processing: fixed handling of non-UTF8 text file encodings in `extractText`
- Update check now correctly compares versions following the `0.x` minor-version scheme (e.g. 0.7 > 0.61), so the manual check no longer offers an "update" to a version that isn't actually newer
- Cancelling an action no longer saves a partial result to history or triggers auto-copy/close
- Sensitive content detection now also scans manual context embedded into the system prompt via `{{kontext}}`
- Fix: a cancelled action resuming late can no longer clobber the state (result, loading indicator) of the next run
- Fix: `ConfigStore` is now thread-safe — config reads from background tasks (history logger) no longer race with writes from the UI

(v0.63 was never published; its changes shipped as part of v0.64)

## v0.62 – 2026-05-29
- File processing: clipboard files (Cmd+C in Finder) now send file content to the LLM instead of the raw file path
- File processing: DOCX, DOC, RTF, ODT, HTML files now extract text via `textutil`
- File processing: XLSX files extract text from embedded XML (`xl/sharedStrings.xml`)
- File processing: PPTX files extract text from slide XMLs
- File processing: Pages, Numbers, Keynote files are OCR-processed via their embedded preview image

## v0.61 – 2026-05-20
- Per-action "Ignore clipboard" setting: each action can now be configured to bypass clipboard input, so the LLM receives only the manual text input — no need to toggle the eye icon in the overlay

## v0.60 – 2026-05-06
- Custom provider settings now show a live "Effective URL" preview (the exact chat endpoint used, including optional `?api-version=` query parameter)
- Model filter section redesigned: Exclude and Include filters each have their own header and description; filter names clarified with "(Exclude)" / "(Include)" labels; Include filter description clarifies that Exclude is applied on top of it
- Fix: crash when deleting a custom provider — SwiftUI ForEach now uses identity-based bindings instead of index-based, preventing out-of-bounds access during the alert dismissal animation

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
