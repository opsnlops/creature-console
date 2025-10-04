# Repository Guidelines

## Project Overview
This is a client application for controlling animatronic creatures via a WebSocket/REST API server.

**Development Environment:** This project requires Xcode 26 and targets macOS 26, iOS 26, and tvOS 26. No older versions are supported. Always use the latest APIs and features available.

**Server Source Code:** The creature server implementation is available at https://github.com/opsnlops/creature-server. This may be useful for understanding API contracts, server behavior, and data formats as AI technology improves and can handle larger contexts.

## Project Structure & Module Organization
- `Sources/Creature Console/` hosts the SwiftUI app, grouped by feature (`Controller`, `Model`, `View`).
  - `Model/` contains SwiftData models for local persistence (AnimationMetadataModel, CreatureModel, PlaylistModel, SoundModel, ServerLogModel)
  - `SwiftDataStore` actor provides concurrency-safe access to the ModelContainer
- `Common/` is a local package dependency shared across targets; review it when updating shared models or protocols.
  - DTOs in Common package must stay in sync with SwiftData models in the app
  - Importer classes (e.g., AnimationMetadataImporter) sync server data to SwiftData models
- `Tests/` contains Swift Package tests for the executable target; Xcode-specific suites live under `Creature Console Tests/`.
- Assets (app icons, sounds, credits) live in `Sources/Creature Console/Assets.xcassets/` and adjacent resource folders.

## Build, Test, and Development Commands
- `swift build` — compiles the SPM targets, validating cross-platform code (CLI and app logic).
  - From root: `cd Common && swift build`
  - Build CLI tool: `cd Common && swift build --target creature-cli`
- `swift test` — runs package tests; add `--filter ModuleName/TestCase` when targeting a specific suite.
  - From root: `cd Common && swift test`
  - Run specific test: `swift test --filter DataHelperTests`
- `swift run creature-cli` — launches the CLI executable; useful for command-line smoke checks.
  - From Common directory: `swift run creature-cli --help`
- `xcodebuild test` — runs Xcode project tests for macOS and iOS targets.
  - macOS: `xcodebuild test -project "Creature Console.xcodeproj" -scheme "Creature Console" -destination "platform=macOS"`
  - iOS: `xcodebuild test -project "Creature Console.xcodeproj" -scheme "Creature Console" -destination "platform=iOS Simulator,name=iPhone 15 Pro"`
- `open Creature\ Console.xcodeproj` — opens the GUI workspace for macOS/iOS/tvOS builds and UI previews.

## Code Quality Philosophy

**IMPORTANT: Always prioritize correctness, quality, and maintainability over speed of implementation.**

- **Correct over Fast**: Take the time to implement solutions properly. A correct solution that takes longer to write is always preferred over a quick but flawed implementation.
- **DRY (Don't Repeat Yourself)**: Avoid code duplication. Extract common patterns into reusable functions, extensions, or computed properties.
- **No Bandaids**: Don't use temporary fixes, workarounds, or delays to mask underlying issues. Identify and fix root causes.
- **Think First, Then Code**: When encountering a problem:
  1. Understand the root cause completely
  2. Design the proper solution
  3. Implement it correctly
  4. Test thoroughly
- **Race Conditions**: When dealing with concurrency (especially SwiftData, actors, or async/await), take time to understand the threading model and prevent race conditions properly rather than adding delays or hoping for the best.
- **User Is Patient**: The developer is willing to wait for well-thought-out solutions. Don't rush.

## Coding Style & Naming Conventions
- Follow Swift API Design Guidelines; prefer descriptive camelCase for variables/functions and PascalCase for types.
- Indent with 4 spaces; align trailing closures and guard returns for readability.
- **IMPORTANT**: Run `swift-format --configuration swift-format.json --in-place <paths>` on ALL modified files before committing.
  - Format single file: `swift-format --configuration swift-format.json --in-place Sources/Common/MyFile.swift`
  - Format directory: `swift-format --configuration swift-format.json --in-place Sources/Common/`
  - Settings: 4 spaces indentation, 100 character line length
- Swift singletons are declared as `static let shared`; mirror existing naming when adding new managers or caches.

## SwiftData Guidelines
- **SwiftData models** live in `Sources/Creature Console/Model/` and use the `@Model` macro.
- **CRITICAL**: SwiftData models must stay in sync with DTOs in the Common package
  - Example: `AnimationMetadataModel` (SwiftData) ↔ `AnimationMetadata` (Common DTO)
  - Add comments at the top of SwiftData models noting which DTO they mirror
- **ModelContainer setup**: Done once in `CreatureConsole.swift` init, then stored in `SwiftDataStore.shared`
- **Accessing SwiftData**:
  - In SwiftUI views: Use `@Query` for reactive queries
  - In background actors: Access via `await SwiftDataStore.shared.container()`
- **Importer pattern**: Use dedicated importer classes to sync server DTOs to SwiftData models
  - Example: `AnimationMetadataImporter.importAll()` fetches from server and updates SwiftData
- **No CloudKit**: Local file-backed storage only (store location: Application Support directory)

## Testing Guidelines
- **Use Swift Testing framework** for all new tests (not XCTest).
  - Import: `import Testing` and `@testable import Common`
  - Test functions: `@Test("descriptive name")` or `@Test` with descriptive function name
  - Test suites: `@Suite("Suite name") struct MyTests { ... }`
  - Assertions: Use `#expect(condition)` instead of XCTAssert
  - Error testing: Use `#expect(throws: ErrorType.self) { try ... }` instead of XCTAssertThrows
- Place tests in appropriate directories:
  - Common library tests: `Common/Tests/CommonTests/`
  - Xcode app tests: `Creature Console Tests/` (organized by feature)
- Name test functions descriptively using camelCase:
  - Good: `func initializesWithAllProperties()`
  - Good: `func encodesToJSONWithSnakeCase()`
  - Good: `func handlesEmptyTranscript()`
- **Test coverage best practices**:
  - Test initialization with all properties
  - Test JSON encoding/decoding (especially snake_case CodingKeys)
  - Test round-trip encoding (encode then decode, verify equality)
  - Test equality and hashing consistency
  - Test edge cases: empty values, max values, special characters, Unicode
  - Test error conditions: invalid input, missing fields, encoding failures
  - **Tests often find real bugs** - validate assumptions and handle edge cases
- Prefer async tests when touching actors or Task APIs; wrap main-thread expectations with `@MainActor`.
- Use mock data and mock implementations for server integrations to prevent regressions.
- **Always run tests before committing**: `cd Common && swift test`

## Commit & Pull Request Guidelines
- Write imperative, present-tense commit subjects (`Add joystick cache primer`); keep to ~72 characters.
- Break significant changes into focused commits that compile and pass tests individually.
- **Before committing**:
  1. Run `swift-format` on all modified files
  2. Run `cd Common && swift test` to verify all tests pass
  3. If modifying UI, test on relevant platforms (macOS, iOS, tvOS)
- Pull requests should include: a concise summary, testing notes (`swift test`, simulator runs), and screenshots for UI tweaks.
- Link tracking issues (e.g., `Fixes #123`) and call out risky areas such as concurrency-sensitive actors or server APIs.

## Continuous Integration
- GitHub Actions runs tests automatically on push to `main` and on all pull requests.
- Workflow: `.github/workflows/tests.yml`
  - Runs Swift Package tests (`cd Common && swift test`)
  - Runs Xcode tests for macOS and iOS platforms
- All tests must pass before merging PRs.
