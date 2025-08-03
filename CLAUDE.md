# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Creature Console is a multi-platform SwiftUI application (macOS, iOS, tvOS) with a shared Swift Package Manager library for controlling "creatures" (animatronic devices) via a WebSocket/REST API server. The project includes both a GUI app and a command-line interface.

**Platform Support:** Always targets the latest versions of macOS, iOS, and tvOS with no backwards compatibility requirements. Favor the newest APIs and features available.

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

#### GUI Application
- **CreatureConsole.swift**: Main app entry point with singleton managers
- **Controller/**: App-specific controllers (caches, joystick handling, events)
- **View/**: SwiftUI views organized by feature (Animations, Creatures, Playlists, etc.)
- **Model/**: GUI-specific models (AudioManager, StorageManager, etc.)

#### CLI Application
- **Sources/CreatureCLI/**: Command-line interface using ArgumentParser
- Commands: animations, creatures, debug, metrics, playlist, sounds, voice, websocket

### Key Singletons and Managers
- `AppState.shared`: Central application state
- `CreatureServerClient.shared`: Server communication
- `AudioManager.shared`: Audio playback management
- `JoystickManager.shared`: Joystick input handling
- Various cache managers for server data

### Communication Patterns
- Server communication via REST API and WebSocket
- WebSocket for real-time data (sensor reports, logs, status updates)
- Caching layer for frequently accessed server data
- SwiftUI @ObservableObject pattern for reactive UI updates

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