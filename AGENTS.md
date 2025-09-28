# Repository Guidelines

## Project Structure & Module Organization
- `Sources/Creature Console/` hosts the SwiftUI app, grouped by feature (`Controller`, `Model`, `View`).
- `Common/` is a local package dependency shared across targets; review it when updating shared models or protocols.
- `Tests/` contains Swift Package tests for the executable target; Xcode-specific suites live under `Creature Console Tests/`.
- Assets (app icons, sounds, credits) live in `Sources/Creature Console/Assets.xcassets/` and adjacent resource folders.

## Build, Test, and Development Commands
- `swift build` — compiles the SPM targets, validating cross-platform code (CLI and app logic).
- `swift test` — runs package tests; add `--filter ModuleName/TestCase` when targeting a specific suite.
- `swift run creature-console` — launches the executable target; useful for CLI-driven smoke checks.
- `open Creature\ Console.xcodeproj` — opens the GUI workspace for macOS/iOS/tvOS builds and UI previews.

## Coding Style & Naming Conventions
- Follow Swift API Design Guidelines; prefer descriptive camelCase for variables/functions and PascalCase for types.
- Indent with 4 spaces; align trailing closures and guard returns for readability.
- Run `swift format --configuration swift-format.json --in-place <paths>` before committing; keep comments concise and purposeful.
- Swift singletons are declared as `static let shared`; mirror existing naming when adding new managers or caches.

## Testing Guidelines
- Use XCTest for unit and integration tests; place new cases beside the code they exercise (e.g., `Model/...Tests.swift`).
- Name tests as `test<Action>_<Expectation>` to surface intent in CI logs.
- Prefer async tests when touching actors or Task APIs; wrap main-thread expectations with `@MainActor`.
- Aim to cover cache updates, message processors, and server integrations with mock data to prevent regressions.

## Commit & Pull Request Guidelines
- Write imperative, present-tense commit subjects (`Add joystick cache primer`); keep to ~72 characters.
- Break significant changes into focused commits that compile and pass tests individually.
- Pull requests should include: a concise summary, testing notes (`swift test`, simulator runs), and screenshots for UI tweaks.
- Link tracking issues (e.g., `Fixes #123`) and call out risky areas such as concurrency-sensitive actors or server APIs.
