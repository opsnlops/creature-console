# VW-000 Swift Monorepo Inventory

**Date:** 2026-09-08

**Tracking issue:** [#91](https://github.com/opsnlops/creature-console/issues/91)

**Architecture:** [`beakys-world.md`](beakys-world.md)

## Baseline

The inventory was performed from a clean `main` branch at `origin/main`. Existing products build
and test successfully with Xcode 26 and Swift 6.2 package manifests.

| Command | Result |
|---|---|
| `swift build` from the repository root | Passed |
| `cd Common && swift build` | Passed |
| `cd Common && swift build --target creature-cli` | Passed |
| `cd Common && swift run creature-cli --help` | Passed |
| `cd Common && swift test` | Passed: 568 tests in 82 suites |
| `xcodebuild test -project "Creature Console.xcodeproj" -scheme "Creature Console" -destination "platform=macOS"` | Passed |
| `xcodebuild test -project "Creature Console.xcodeproj" -scheme "Creature Console" -destination "platform=iOS Simulator,id=<available-device>"` | Passed |

The root Swift build reports two pre-existing warnings:

- `Creature-Console-Info.plist` is unhandled by the root SwiftPM target.
- `Text + Text` in `AdHocAssetsView.swift` is deprecated on macOS 26.

Neither warning blocks VW-001. They should not be folded into the world foundation work.

## Existing products and targets

### Root Swift package and Xcode project

The root `Package.swift` exposes one executable product and target:

- `creature-console` / `CreatureConsole`

It consumes the local `Common` package products `Common` and `PlaylistRuntime`, plus Apple-only UI
dependencies. Its source path is `Sources/Creature Console`.

`Creature Console.xcodeproj` contains these application and test targets:

- `Creature Console`
- `Creature Console Tests`
- `Creature TV`
- `Creature TVTests`
- `Creature TVUITests`

Shared schemes also expose the `Common` package tests and Linux executables.

### `Common` Swift package

`Common/Package.swift` is already the natural home for cross-platform libraries and independently
deployable Linux executables.

| Target | Kind | Direct internal dependencies | Current responsibility |
|---|---|---|---|
| `Common` | Library | None | Creature Server DTOs, REST/WebSocket client, shared networking and identifiers |
| `PlaylistRuntime` | Library | `Common` | Shared playlist runtime behavior |
| `MQTTSupport` | Library | None | MQTT connection and publication machinery |
| `Observability` | Library | None | OTel/logging bootstrap for long-lived services and CLI tools |
| `CreatureMigration` | Library | None | MongoKitten migration and backfill building blocks |
| `creature-cli` | Executable | `Common`, `CreatureMigration`, `Observability` | Creature Server command-line client and relays |
| `creature-mqtt` | Executable | `Common`, `MQTTSupport`, `Observability` | Creature Server WebSocket to MQTT/Home Assistant bridge |
| `creature-agent` | Executable | `Common`, `MQTTSupport`, `Observability` | Current MQTT-driven LLM-to-speech agent |
| `CommonTests` | Test | `Common`, `creature-cli`, `CreatureMigration` | Shared contracts, CLI, protocol, and utility tests |
| `CreatureAgentTests` | Test | `creature-agent`, `creature-mqtt` | Agent and MQTT behavior/metrics tests |

MongoKitten is already a package dependency, but it is intentionally isolated from `Common` by the
`CreatureMigration` target. The world persistence target should preserve that isolation.

## Existing integration seams

### Creature Server client and WebSocket processing

`CreatureServerClient` lives at
`Common/Sources/Common/Controller/Server/CreatureServerClient.swift`. It is a public, reusable,
`Sendable` client with REST helpers, W3C trace-header injection, and Apple/Linux WebSocket
implementations.

`MessageProcessor` lives at
`Common/Sources/Common/Controller/Server/RESTful/MessageProcessor.swift`. The WebSocket ingestion
pipeline awaits processor methods one at a time, preserving server arrival order. The protocol
already covers the initial world-ingestion surface: board and motor sensors, controller activity,
idle state, jobs, counters, warnings, and other runtime messages.

Existing specialized processors prove the intended extension model:

- `Sources/Creature Console/Controller/Server/SwiftMessageProcessor.swift` maps messages into GUI
  and SwiftData state.
- `Common/Sources/CreatureMQTT/MQTTMessageProcessor.swift` maps the same messages into scalar MQTT
  state with publication deduplication.
- `Common/Sources/CreatureCLI/CLIMessageProcessor.swift` renders messages for operators.

`WorldMessageProcessor` should therefore be a new implementation in a new `WorldIntegration`
target. It should use its own `CreatureServerClient` connection (or a deliberately introduced
fan-out abstraction if later required), not import Console models and not route through MQTT.

### Current agent boundary

The current `creature-agent` is concentrated under `Common/Sources/CreatureAgent`:

- `runCommand.swift` wires configuration, OTel, MQTT, local/OpenAI model clients, Creature Server,
  and service lifecycle.
- `MQTTAgentListener.swift` owns topic subscription, retained-message handling, and concurrency
  limits.
- `AgentEventProcessor.swift` combines topic lookup, stale/duplicate filtering, area cooldowns,
  model invocation, text sanitization, streaming/non-streaming speech, and server submission.
- `LocalLLMClient` and its parser/history utilities provide the Mistral-compatible local model path
  that VW-014 and VW-015 should preserve.

VW-014 can add the world-resident input alongside the current path behind a feature flag. MQTT
types remain isolated until parity is demonstrated, which avoids a flag-day rewrite.

### Observability

`Common/Sources/Observability/OTelBootstrap.swift` bootstraps logs, traces, and metrics and returns
services suitable for `ServiceGroup`. It is package-visible, so new targets inside the same
`Common` package can reuse it without widening its public API immediately. `CreatureServerClient`
already injects standard trace context into HTTP requests.

World-specific span names, safe attributes, propagation contracts, and persisted trace references
belong in `WorldCore`/world application targets, while SDK bootstrap remains in `Observability`.

## Current CI and release surfaces

| Workflow/path | Current behavior |
|---|---|
| `.github/workflows/build.yml` | Runs root `swift build` on macOS |
| `.github/workflows/tests.yml` | Runs `Common` package tests plus macOS and iOS Xcode tests |
| `.github/workflows/build-deb.yml` | Builds amd64 and arm64 packages in Debian Trixie with Swift 6.3.3 |
| `debian/control` | Defines `creature-cli`, `creature-mqtt`, `creature-agent`, and `creature-world` binary packages |
| `debian/rules` | Builds and installs all four Swift executables and shell completions |
| `build_deb.sh` / `clean_deb.sh` | Wrap the existing Debian metadata and cleanup flow |

The Debian workflow currently uploads `.deb` and `.ddeb` artifacts but does not yet perform the
clean-container install, linkage, service validation, upgrade, uninstall, or persistence checks
required by VW-024.

Current `debian/rules` installs executables under `/usr/bin`. The world architecture specifies a
canonical `/bin/<executable>` path under Debian's merged-`/usr` convention. VW-024 must resolve this
deliberately and update package manifests, units, scripts, tests, and documentation consistently;
VW-001 should not alter packaging paths.

## Least-disruptive target placement

Add the platform-neutral and Linux-side targets as siblings in `Common/Package.swift`. This keeps
atomic contract changes possible and reuses current dependencies without making `Common` depend on
world semantics.

```text
Common (Creature Server contracts)       WorldCore (world contracts)
              |                              |
              +------> WorldIntegration <----+
                                             |
                 +---------------------------+------------------------+
                 |             |             |                        |
          CreatureWorld   CreatureAgent   WorldViewerClient   InformationBridgeCore
                 |             |                                      |
          MongoKitten +   Common server                    Apple-only adapters remain
          Observability   client + OTel                    outside platform-neutral core
```

Recommended additions:

| Target/product | Location | Dependencies and boundary |
|---|---|---|
| `WorldCore` | `Common/Sources/WorldCore` | Platform-neutral; must not depend on `Common`, MongoKitten, MCP, or Apple frameworks |
| `WorldIntegration` | `Common/Sources/WorldIntegration` | Depends on `WorldCore` and `Common`; owns `WorldMessageProcessor` |
| `CreatureWorld` / `creature-world` | `Common/Sources/CreatureWorld` | Depends on `WorldCore`, `Observability`, MongoKitten, HTTP/WebSocket implementation |
| `WorldViewerClient` | `Common/Sources/WorldViewerClient` | Depends on `WorldCore`; contains transport/client logic, not SwiftUI views |
| `InformationBridgeCore` | `Common/Sources/InformationBridgeCore` | Depends on `WorldCore`; protocols, ledger/outbox, privacy policy, and fakes only |
| `CreatureAppSupport` | `Common/Sources/CreatureAppSupport` | Apple-only, product-neutral UI, connection, and shared Keychain infrastructure for Console, Communicator, and Scribe |
| `BeakyCommunicatorCore` | `Common/Sources/BeakyCommunicatorCore` | Platform-neutral lease, synchronization, and delivery building blocks shared by the Beaky apps and gateway |
| `HomeAssistantWorldAdapter` | `Common/Sources/HomeAssistantWorldAdapter` | Depends on `WorldCore`, `Observability`, and selected WebSocket client |
| `WorldMCP` | `Common/Sources/WorldMCP` | Depends on world query services; isolates MCP SDK and transport types |
| `CreatureCommunicatorGateway` | `Common/Sources/CreatureCommunicatorGateway` | Future Linux executable; depends on communication contracts and gateway infrastructure |

Create World Viewer, Creature Scribe/`creature-scribed`, and Beaky Communicator as separate Xcode
application/daemon targets with their own entitlements and deployment metadata. Their reusable,
testable logic should live in the package targets above. Do not add world views to Creature Console
or Apple frameworks to `WorldCore`.

## Dependency rules to enforce in VW-001

1. `Common` must not depend on `WorldCore`.
2. `WorldCore` must compile on Linux and macOS and contain no transport, persistence, MCP, or
   Apple-only framework code.
3. `WorldIntegration` is the only initial target that needs both Creature Server and world
   contracts.
4. Simulator repositories depend on MongoKitten; world value types do not.
5. Viewer and MCP use the same authorized query/application services rather than reading MongoDB
   directly.
6. Information Bridge helpers feed `creature-scribed`; they do not deliver directly to the
   simulator or expose raw private data to agents.
7. Each separately deployed Linux executable must be classified in the Debian product matrix.

## Decisions intentionally deferred

The following need focused ADRs or spikes and do not block VW-001:

- Linux HTTP/WebSocket framework selection.
- Atomic world-sequence allocation and MongoDB transaction strategy.
- Initial LAN authentication mechanism.
- Separate-process versus embedded deployment for HA and MCP adapters.
- One-agent-per-process versus isolated multi-character sessions.
- Exact Apple source acquisition and entitlement details.
- Final `/bin` versus `/usr/bin` packaging implementation under merged `/usr`.
