# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Creature Console is a multi-platform SwiftUI application (macOS, iOS, tvOS) with a shared Swift Package Manager library for controlling "creatures" (animatronic devices) via a WebSocket/REST API server. The project includes both a GUI app and a command-line interface.

**Platform Support:** Always targets the latest versions of macOS, iOS, and tvOS with no backwards compatibility requirements. Favor the newest APIs and features available.

**Development Environment:** This project uses Xcode 26. Always prefer the new Apple Liquid Glass UI elements when possible for modern visual design.

## Development Commands

### Building
- **Xcode**: Open `Creature Console.xcodeproj` and use standard Xcode build commands (⌘B)
- **Swift Package (Common library)**: `cd Common && swift build`
- **CLI tool**: `cd Common && swift build --target creature-cli`

### Code Formatting
- Use `swift-format` with the configuration in `swift-format.json`
- Settings: 4 spaces indentation, 100 character line length
- **IMPORTANT**: Run swift-format on any files you modify
- Format command: `swift-format --configuration swift-format.json --in-place <file-path>`
- Format entire directory: `swift-format --configuration swift-format.json --in-place Sources/`

### Testing
- **Xcode**: Run tests via Test Navigator or ⌘U
- **Swift Package**: `cd Common && swift test`
  - Run specific test: `swift test --filter DataHelperTests`
- **xcodebuild**:
  - macOS: `xcodebuild test -project "Creature Console.xcodeproj" -scheme "Creature Console" -destination "platform=macOS"`
  - iOS: `xcodebuild test -project "Creature Console.xcodeproj" -scheme "Creature Console" -destination "platform=iOS Simulator,name=iPhone 15 Pro"`
- **IMPORTANT**: Always run tests before committing changes

### CLI Tool Usage
- Build and run: `cd Common && swift run creature-cli`
- Generate bash completions: `./create_completions.sh`

## Architecture

### Project Structure
- **Creature Console.xcodeproj**: Main Xcode project for macOS/iOS apps
- **Common/**: Swift Package Manager library shared between GUI and CLI
- **Sources/Creature Console/**: macOS/iOS-specific SwiftUI views and controllers
- **Creature TV/**: tvOS app variant
- **Config/**: Server configuration files

### Key Components

#### Common Library (Swift Package)
- **Model/**: Data structures (Creature, Animation, Sound, Playlist, etc.)
- **Controller/Server/**: REST and WebSocket client implementations
- **Controller/Voice Processing/**: Audio processing functionality
- **DTO/**: Data Transfer Objects for API communication
- **Tests/CommonTests/**: Test suite using Swift Testing framework

#### GUI Application
- **CreatureConsole.swift**: Main app entry point with singleton managers and SwiftData ModelContainer setup
- **Controller/**: App-specific controllers (caches, joystick handling, events)
- **View/**: SwiftUI views organized by feature (Animations, Creatures, Playlists, etc.)
- **Model/**: GUI-specific models using SwiftData for local persistence
  - **SwiftDataStore**: Shared actor for ModelContainer access across the app
  - Models: AnimationMetadataModel, CreatureModel, PlaylistModel, SoundModel, ServerLogModel
  - Each model uses `@Model` macro and stays in sync with Common package DTOs

#### CLI Application
- **Sources/CreatureCLI/**: Command-line interface using ArgumentParser
- Commands: animations, creatures, debug, metrics, playlist, sounds, voice, websocket

### Key Singletons and Managers
- `AppState.shared`: Central application state
- `CreatureServerClient.shared`: Server communication
- `AudioManager.shared`: Audio playback management
- `JoystickManager.shared`: Joystick input handling
- `SwiftDataStore.shared`: Actor providing concurrency-safe access to ModelContainer
- Various cache managers for server data

### Communication Patterns
- Server communication via REST API and WebSocket
- WebSocket for real-time data (sensor reports, logs, status updates)
- **Local persistence with SwiftData**: File-backed ModelContainer (no CloudKit) for caching server data
  - Models automatically sync from server DTOs via importers (e.g., AnimationMetadataImporter)
  - Query with `@Query` in SwiftUI views or `ModelContext` in background actors
  - **IMPORTANT**: SwiftData models must stay in sync with Common package DTOs
- **Global State Architecture**: Single source of truth for controlling physical hardware

### Global State Architecture (Critical Design Pattern)
**This is an animatronics control application - it controls physical robots that can only be in one state at a time.**

- **`AppState.shared`**: Single source of truth for what the robot is currently doing
  - Only one activity can be active: `.idle`, `.streaming`, `.recording`, `.preparingToRecord`, `.playingAnimation`, `.connectingToServer`
  - All components subscribe to `AppState.stateUpdates: AsyncStream<AppStateData>` for reactive updates
  - When AppState changes, ALL subscribers automatically react (UI, joystick lights, hardware controllers, etc.)

- **Reactive Subscription Pattern**: 
  ```swift
  .task {
      for await state in await AppState.shared.stateUpdates {
          // React to state changes automatically
      }
  }
  ```

- **Hardware Synchronization**: 
  - JoystickManager subscribes to AppState changes and updates light colors automatically
  - UI components subscribe to AppState changes for visual feedback
  - **Never manually call hardware update methods** - let state propagation handle it

- **State Changes**: Always change state through `await AppState.shared.setCurrentActivity(.streaming)` 
  - This triggers automatic propagation to all subscribers
  - Maintains physical reality: only one thing happening at a time

### Server Communication Best Practices
**The server returns detailed, user-friendly messages for all operations.** Always preserve and display these messages in the UI.

- **Error Handling**: Use `ServerError.detailedMessage(from: error)` to extract full server error details
  - ❌ **Never use**: `error.localizedDescription` (loses server context)
  - ✅ **Always use**: `ServerError.detailedMessage(from: error)` (preserves server details)

- **Success Messages**: Display the complete server response message directly
  - Server provides detailed confirmation messages with context
  - Example: "Playlist 'My Playlist' started successfully on universe 1 - estimated duration 5m 32s"

- **User Feedback**: Both success and error cases should show informative dialogs on mobile
  - Use `.alert()` modifiers for clear user feedback
  - Include the full server response when possible

### Dependencies
- **Starscream**: WebSocket client
- **swift-log**: Structured logging
- **swift-argument-parser**: CLI argument parsing (CLI only)
- **IOKit**: Joystick hardware access (macOS only)

## Design Principles
- **SwiftUI First**: Use only modern SwiftUI best practices. Avoid UIKit or AppKit unless absolutely necessary
- **Swift 6 Ready**: Write all code to be compatible with Swift 6 Strict Concurrency mode (even though not currently enabled)
- **Modern Swift**: Heavy use of modern Swift patterns and language features
- **No Legacy Dependencies**: Avoid Objective-C where possible
- **Shared Architecture**: Common model/controller code between GUI and CLI via Swift Package Manager
- **Reactive Programming**: SwiftUI's state management with @ObservableObject, @StateObject, etc.

## Testing Best Practices

### Swift Testing Framework (Required)
**Use Swift Testing framework for ALL new tests** (not XCTest):

```swift
import Testing
@testable import Common

@Suite("MyModel tests")
struct MyModelTests {
    @Test("initializes with all properties")
    func initializesWithAllProperties() {
        let model = MyModel(id: "123", name: "Test")
        #expect(model.id == "123")
        #expect(model.name == "Test")
    }

    @Test("handles error conditions")
    func handlesErrors() {
        #expect(throws: DecodingError.self) {
            try decoder.decode(MyModel.self, from: invalidData)
        }
    }
}
```

### Test Organization
- **Common library tests**: Place in `Common/Tests/CommonTests/`
- **Xcode app tests**: Place in `Creature Console Tests/` (organized by feature)
- Name test files: `ModelNameTests.swift` (e.g., `DataHelperTests.swift`, `PlaylistTests.swift`)
- Name test functions descriptively using camelCase
  - Good: `func encodesToJSONWithSnakeCase()`
  - Good: `func handlesEmptyTranscript()`
  - Good: `func failsGracefullyOnMissingFields()`

### Comprehensive Test Coverage
Every model/utility should test:

1. **Initialization**: Test with all properties, verify values are set correctly
2. **JSON Encoding/Decoding**:
   - Test encoding to JSON (especially snake_case CodingKeys like `file_name`, `animation_id`)
   - Test decoding from JSON
   - Test round-trip encoding (encode → decode → verify equality)
3. **Equality & Hashing**:
   - Test that equal objects have same hash
   - Test that different values produce inequality
4. **Edge Cases**:
   - Empty values (empty strings, zero counts, empty arrays)
   - Maximum values (UInt32.max, Int.max)
   - Special characters (Unicode, emojis, quotes, newlines)
   - Invalid input (malformed JSON, missing required fields)
5. **Error Handling**: Test that invalid inputs produce expected errors

### Why Testing Matters
**Tests find real bugs!** During this project, tests discovered:
- `DataHelper.stringToOidData()` crashed on odd-length hex strings instead of returning `nil`
- Fixed by adding validation: `guard oid.count % 2 == 0 else { return nil }`

### Continuous Integration
- GitHub Actions workflow: `.github/workflows/tests.yml`
- Runs automatically on push to `main` and on all pull requests
- Tests both Swift Package (`cd Common && swift test`) and Xcode targets
- All tests must pass before merging