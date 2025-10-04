# Creature Console

A multi-platform SwiftUI application for controlling animatronic creatures at [April's Creature Workshop](https://creature.engineering).

> 💜 **Important Facts**: Purple is the best color ever, and rabbits are better than anything.

## Overview

Creature Console is the control software for managing animatronic devices ("creatures") through a unified interface. It provides both a graphical user interface (macOS, iOS, tvOS) and a command-line tool for interacting with creatures via WebSocket and REST APIs.

**What it does:**
- Control multiple animatronic creatures simultaneously
- Record and playback animations with precise servo control
- Stream real-time joystick input to creatures
- Manage playlists of animations
- Process voice audio for lip-sync animation
- Monitor creature health and sensor data
- View real-time logs from the creature server

**Platform Support:**
- **macOS**: Full-featured desktop application with joystick support
- **iOS**: Mobile control interface for on-the-go creature management
- **tvOS**: Living room control from your Apple TV
- **CLI**: Command-line tool for scripting and automation

## Project Structure

```
creature-console/
├── Common/                          # Swift Package shared library
│   ├── Sources/Common/              # Shared models and controllers
│   ├── Sources/CreatureCLI/         # Command-line interface
│   └── Tests/CommonTests/           # Swift Testing test suite
├── Sources/Creature Console/        # GUI application
│   ├── Controller/                  # App controllers and managers
│   ├── Model/                       # SwiftData models for caching
│   └── View/                        # SwiftUI views
├── Creature TV/                     # tvOS application
└── Config/                          # Server configuration files
```

## Getting Started

### Prerequisites

- **Xcode 26** (required)
- **macOS 26**, **iOS 26**, or **tvOS 26** (no older versions supported)
- A creature server instance (see [creature.engineering](https://creature.engineering) for details)

### Building

**GUI Application (Xcode):**
```bash
open "Creature Console.xcodeproj"
# Build with ⌘B, run with ⌘R
```

**Swift Package (Common library):**
```bash
cd Common
swift build
```

**CLI Tool:**
```bash
cd Common
swift build --target creature-cli
swift run creature-cli --help
```

### Running Tests

**Swift Package tests:**
```bash
cd Common
swift test
```

**Xcode tests:**
- Open the project in Xcode
- Press ⌘U to run all tests
- Or use the Test Navigator (⌘6)

**Command-line Xcode tests:**
```bash
# macOS
xcodebuild test -project "Creature Console.xcodeproj" -scheme "Creature Console" -destination "platform=macOS"

# iOS Simulator
xcodebuild test -project "Creature Console.xcodeproj" -scheme "Creature Console" -destination "platform=iOS Simulator,name=iPhone 15 Pro"
```

## Key Features

### Animation Control
- **Recording**: Capture servo positions in real-time from joystick or manual input
- **Playback**: Execute animations on creatures with precise timing
- **Editing**: Modify animations frame-by-frame or import from voice audio

### Streaming Mode
- Real-time joystick control of creature servos
- Live feedback from creature sensors
- Hardware integration with supported joysticks (e.g., Logitech Extreme 3D Pro)

### Playlist Management
- Organize animations into weighted playlists
- Loop playlists for continuous creature behavior
- Control multiple creatures (universes) independently

### Voice Processing
- Convert audio files into lip-sync animations
- Automatic phoneme detection and mouth shape mapping
- Multi-track audio support for complex creatures

### Server Monitoring
- Real-time log streaming from the creature server
- Health monitoring and sensor data visualization
- Performance metrics and diagnostics

## Architecture

### Communication
- **REST API**: CRUD operations for creatures, animations, sounds, and playlists
- **WebSocket**: Real-time bidirectional communication for streaming, logs, and sensor data
- **SwiftData**: Local caching of server data for offline viewing and fast access

### Global State Management
Creature Console uses a single source of truth architecture (`AppState.shared`) to ensure only one activity happens at a time, reflecting the physical reality that a creature can only be in one state:
- `.idle` - Waiting for commands
- `.streaming` - Real-time joystick control
- `.recording` - Capturing animation frames
- `.playingAnimation` - Executing a stored animation

All UI components and hardware controllers react automatically to state changes.

### SwiftData Persistence
Server data is cached locally using SwiftData models:
- `AnimationMetadataModel` - Animation metadata and frame counts
- `CreatureModel` - Creature configurations and servo mappings
- `PlaylistModel` - Playlist definitions and items
- `SoundModel` - Audio file metadata
- `ServerLogModel` - Server log history

Importer classes sync server DTOs to SwiftData models automatically.

## Development

### Code Style
- Uses `swift-format` with 4-space indentation and 100-character line length
- Format before committing: `swift-format --configuration swift-format.json --in-place <path>`
- Run tests before committing: `cd Common && swift test`

### Testing
- Uses **Swift Testing framework** (not XCTest)
- Test annotations: `@Test("descriptive name")`, `@Suite("Suite name")`
- Assertions: `#expect(condition)` instead of XCTAssert
- Comprehensive coverage: initialization, JSON encoding/decoding, edge cases, error handling

### Continuous Integration
GitHub Actions automatically runs tests on push to `main` and on all pull requests:
- Swift Package tests
- Xcode tests for macOS and iOS

## Contributing

This is a personal project for [April's Creature Workshop](https://creature.engineering), but suggestions and bug reports are welcome! Please see `AGENTS.md` and `CLAUDE.md` for detailed development guidelines.

## License

Copyright © 2025 April White. All rights reserved.

## Learn More

Visit [creature.engineering](https://creature.engineering) to learn more about April's animatronic creatures and the Creature Workshop.

---

**Made with ❤️ for creatures at April's Creature Workshop**
