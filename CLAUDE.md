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
