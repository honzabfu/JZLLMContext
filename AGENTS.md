# JZLLMContext agent instructions

Read and follow `CLAUDE.md` before working in this repository. It is the shared
source of project rules for all coding agents; keep those rules there rather
than duplicating them here. Read the relevant sections of `README.md` for the
architecture and user-facing behavior.

This is a Swift 6 macOS 15+ menu bar app using SwiftUI and AppKit. Application
code lives in `Sources/JZLLMContext`, and Swift Testing tests live in
`Tests/JZLLMContextTests`. `project.yml` is the XcodeGen source of truth: run
`xcodegen generate` before building or testing, and change project configuration
there rather than editing the generated `.xcodeproj` directly.

When the user requests a rebuild/install/relaunch, read and follow
`.claude/commands/rebuild.md`. When the user requests a release, read and follow
`.claude/commands/release.md`; interpret `$ARGUMENTS` as the version supplied by
the user, if any. These workflows apply only when requested, not merely because
their instruction files have been read.

`.claude/settings.json` and `.claude/settings.local.json` configure Claude Code.
They do not grant permissions to other agents; use the active environment's
permissions and approval mechanism.
