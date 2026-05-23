# DMX Fixture Support — Swift Client

## Context

The creature-server (v3.11.2, in prod at `server.prod.chirpchirp.dev`) added first-class support for **DMX fixtures** — generic lighting/effects devices configured separately from `Creature`. The Creature Console is the *only* way to manage them: the server's MongoDB is authoritative, the Swift app is the source-of-truth editor, and there is **no on-disk config or controller-registration step** to push fixtures. Full spec: `~/code/creature-server/plan/dmx-fixture.md` (the "JSON Schema Reference" section is the canonical contract).

A `DmxFixture` has:
- **Identity**: `id` (UUID), `name`, `type` (`light`/`smoke_machine`/`fogger`/`generic`)
- **DMX wiring**: `channel_offset`, `assigned_universe` (nullable, persisted), `channels[]` (`offset`, `name`, `kind`)
- **Behavior**: `patterns[]` (named DMX snapshots with `fade_in_ms`/`hold_ms`/`fade_out_ms`) and `bindings[]` (declarative triggers tying a creature's `(reason, state)` activity transitions to a pattern on this fixture)

The intended outcome: a user can fully manage fixtures (CRUD, universe assignment, manual pattern triggers, validation, color/value editing) from the Creature Console on macOS/iOS; tvOS stays in sync via the data layer but does not ship editing UI; and animations can optionally drive a fixture instead of a creature via the new `Track.fixture_id` field.

## Decisions (confirmed)

1. **Scope**: ship everything in one PR — Common DTOs/models, SwiftData layer, full CRUD UI, manual trigger, and `Track.fixtureId` plumbing.
2. **Light pattern editor**: dual editor — a `ColorPicker` that maps RGB(W) into channels by `kind` (`color_red`/`color_green`/`color_blue`/`color_white`/`master_dimmer`) **plus** raw per-channel sliders always visible underneath.
3. **tvOS**: register `DmxFixtureModel` in the tvOS `ModelContainer` and subscribe to cache invalidation, but no editor screens.
4. **Universe assignment**: inline field on the fixture detail editor; save action calls `PUT /universe` **separately** from the main fixture upsert so a universe-only change persists even when nothing else changed.

## Implementation Plan

### 1 — Common package: model + DTOs + REST

New files under `Common/Sources/Common/Model/DmxFixture/`:

- `DmxFixture.swift` — `public final class DmxFixture: Identifiable, Hashable, Equatable, Codable, Sendable` matching the JSON schema. Mirror the shape of `Common/Sources/Common/Model/Creature/Creature.swift:1-130` (manual `init(from:)` / `encode(to:)` with `decodeIfPresent` defaults; explicit `==` and `hash`; `mock()` extension).
- `FixtureChannel.swift`, `FixturePattern.swift`, `FixturePatternValue.swift`, `FixtureBinding.swift` — nested `struct`s (`Codable, Hashable, Equatable, Sendable, Identifiable` where it makes sense). All snake_case mappings via `CodingKeys`.
- `FixtureType.swift` — `public enum FixtureType: String, Codable, CaseIterable, Sendable` (`light`, `smokeMachine`, `fogger`, `generic`) with snake_case raw values and a "be liberal — unknown decodes to `.generic`" custom `init(from:)`.
- `ActivityReason.swift`, `ActivityState.swift` — `String` enums matching the server's `runtime::ActivityReason` / `runtime::ActivityState` (used for binding filters; `null` = wildcard, modeled as `Optional`).

In `Common/Sources/Common/Model/DTO/`:

- `DmxFixtureListDTO.swift` — `{count: Int32, items: [DmxFixture]}` mirroring `CreatureListDTO`.
- `SetFixtureUniverseDTO.swift` — `{universe: UInt32}` request body.
- `TriggerFixturePatternDTO.swift` — `{stop_after_ms: UInt32?}` request body.
- `FixtureConfigValidationDTO.swift` — `{valid: Bool, fixture_id: String, missing_creature_ids: [String], error_messages: [String]}` (matches the server's validate response).

In `Common/Sources/Common/Types.swift`:
- Add `public typealias DmxFixtureIdentifier = String` and `public typealias FixturePatternIdentifier = String`.

In `Common/Sources/Common/Model/CacheInvalidation/CacheInvalidation.swift:7`:
- Add `case fixture = "fixture"` before `.unknown`.

In `Common/Sources/Common/Model/Animation/Track.swift`:
- Add `public var fixtureId: DmxFixtureIdentifier?` (optional — exactly one of `creatureId`/`fixtureId` should be set; on encode emit only when non-nil; on decode use `decodeIfPresent`). Keep `creatureId` non-optional for now to stay back-compat with the existing wire format — the dual-validity check only enforced at edit-time in UI and on the server.

New `Common/Sources/Common/Controller/Server/RESTful/FixtureMethods.swift` — extension on `CreatureServerClient`, mirroring `CreatureMethods.swift` and `PlaylistMethods.swift:153-163`:

| Method | Endpoint | Helper |
|---|---|---|
| `getAllFixtures()` | `GET  /fixture` | `fetchData` → `DmxFixtureListDTO` → `.items` |
| `getFixture(id:)` | `GET  /fixture/{id}` | `fetchData` |
| `upsertFixture(_ fixture: DmxFixture)` | `POST /fixture` | `sendData(method: "POST", body: fixture, returnType: DmxFixture.self)` |
| `deleteFixture(id:)` | `DELETE /fixture/{id}` | `sendData(method: "DELETE", body: EmptyBody(), returnType: StatusDTO.self)` (same pattern as `PlaylistMethods.swift:163`) |
| `validateFixture(rawJson:)` | `POST /fixture/validate` | `sendRawJson` → `FixtureConfigValidationDTO` |
| `setFixtureUniverse(id:, universe:)` | `PUT  /fixture/{id}/universe` | `sendData(method: "PUT", body: SetFixtureUniverseDTO, ...)` |
| `clearFixtureUniverse(id:)` | `DELETE /fixture/{id}/universe` | `sendData(method: "DELETE", body: EmptyBody(), returnType: StatusDTO.self)` |
| `triggerPattern(fixtureId:, patternId:, stopAfterMs:)` | `POST /fixture/{id}/pattern/{pid}/trigger` | `sendData(method: "POST", body: TriggerFixturePatternDTO, returnType: StatusDTO.self)` |

All URLs built with `makeBaseURL(.http) + "/fixture..."`. No new error cases needed in `ServerError` — existing `dataFormatError`/`notFound`/`conflict`/`serverError` cover the response codes the server uses.

### 2 — Common tests

New `Common/Tests/CommonTests/DmxFixtureTests.swift` (Swift Testing framework — see CLAUDE.md):
- JSON round-trip for the canonical fixture from the spec.
- snake_case key mapping for every field (`channel_offset`, `assigned_universe`, `pattern_id`, `on_reason`, `on_state`, `creature_id`, `fade_in_ms`, `hold_ms`, `fade_out_ms`).
- Unknown `type` decodes to `.generic` (be liberal).
- Decoding tolerates missing `patterns`/`bindings`/`assigned_universe` (defaults to `[]` / `nil`).
- Equality + hashing for the root type.

New `Common/Tests/CommonTests/TrackFixtureIdTests.swift`:
- Existing Track JSON (no `fixture_id`) decodes with `fixtureId == nil` (back-compat).
- New Track JSON with `fixture_id` decodes correctly.
- Encoding emits `fixture_id` only when set.

### 3 — GUI app: SwiftData models + importer

The fixture's nested children (channels/patterns/bindings) are small and always loaded with the parent. **Avoid `@Relationship` modeling for them** — flatten into `Data` columns holding JSON-encoded blobs. Rationale: the editor always works on the entire fixture, the wire format is one document, and inputs/playlist-items relationships in the current code base have already proven painful (see `CreatureImporter.swift:33-35` which has to `delete` children explicitly before reassigning). One `@Model` keeps the upsert path simple.

New under `Sources/Creature Console/Model/DmxFixture/`:

- `DmxFixtureModel.swift` — `@Model final class`:
  ```
  @Attribute(.unique) var id: String
  var name: String
  var typeRaw: String                 // FixtureType.rawValue
  var channelOffset: Int
  var assignedUniverse: Int?          // nil = unassigned
  var channelsJSON: Data              // [FixtureChannel] encoded
  var patternsJSON: Data              // [FixturePattern] encoded
  var bindingsJSON: Data              // [FixtureBinding] encoded
  ```
  - `convenience init(dto:)` and `toDTO()` (mirrors `CreatureModel.swift` extension; use `JSONEncoder`/`JSONDecoder` for the blob columns).
  - Computed `channels`/`patterns`/`bindings` getters that decode the blobs (cached property optional — keep it simple, decode on access; the editor uses its own in-memory `DmxFixture` copy via `toDTO()`).

- `DmxFixtureImporter.swift` — `@ModelActor actor` mirroring `AnimationMetadataImporter.swift:11-53`:
  - `func upsertBatch(_ dtos: [Common.DmxFixture]) async throws` — fetch existing, transaction, update-in-place or insert.
  - `func deleteAllExcept(ids: Set<String>) async throws`.

### 4 — App wiring (startup + cache invalidation)

`Sources/Creature Console/CreatureConsole.swift:118-122` (macOS/iOS) — add `DmxFixtureModel.self` to the `ModelContainer(for:)` list.

`Creature TV/Creature_TVApp.swift:89-93` (tvOS) — same addition.

`Sources/Creature Console/View/AppBootstrapper.swift`:
- Add `importFixturesIntoSwiftData()` private method following the exact shape of `importAnimationsIntoSwiftData()` (lines 116-132).
- Add it to both `startIfNeeded()` parallel `async let` blocks (lines 22-32) and `refreshCachesAfterWake()` (lines 43-53). Widen the result tuple and switch arms in `handleImportResults` to cover the fifth slot.

`Sources/Creature Console/Controller/Server/CacheInvalidationProcessor.swift`:
- Add `static nonisolated(unsafe) private var loadFixturesTask: Task<Void, Never>? = nil` next to the other task vars (line 13-16).
- Add `case .fixture: rebuildFixtureCache(deleteStaleEntries: true)` to the switch at line 19.
- Add `rebuildFixtureCacheAsync` + `rebuildFixtureCache` pair following the existing template (mirror lines 41-90).
- Add the new rebuild call to `rebuildAllCaches` (line 247) for the all-caches refresh path.

### 5 — UI (macOS + iOS only)

All new views under `Sources/Creature Console/View/Fixtures/`, gated behind `#if os(macOS) || os(iOS)` where they're inserted into the sidebar.

`Sources/Creature Console/View/TopContentView.swift` — add a new `Section("Fixtures")` after `Section("Playlists")` (around the existing line 170 region), guarded `#if os(iOS) || os(macOS)`:
```
Section("Fixtures") {
    NavigationLink { FixturesTable() } label: {
        Label("List All", systemImage: "lightbulb.led")
    }
    NavigationLink { FixtureEditor(createNew: true) } label: {
        Label("Create New", systemImage: "plus.circle")
    }
}
```

**`FixturesTable.swift`** — list view (mirror `PlaylistsTable.swift:38-79`):
- `@Query(sort: \DmxFixtureModel.name)` + a `Table` with columns for name, type, universe, channel count.
- Context menu / toolbar: Edit, Delete (with confirmation dialog like `AnimationTable.swift:236-253`), Copy ID.
- Tap → `NavigationLink` to `FixtureEditor(fixture:)`.

**`FixtureEditor.swift`** — the main detail/edit view. Operates on a local mutable `@State var fixture: DmxFixture` copy (initialized from the model or a fresh template when `createNew == true`). Layout: vertical `Form`/`ScrollView` with these sections, each in a `GroupBox` or `.thinMaterial` card:

1. **Identity** — name `TextField`, type `Picker` (FixtureType.allCases), id (read-only, copyable).
2. **DMX wiring** — `channel_offset` numeric field with live validation (`channel_offset + max(channels.offset) ≤ 511`); **Universe assignment**: a `Picker`/`TextField` for universe number with a dedicated "Apply Universe" button right next to it that calls `setFixtureUniverse` independently (or `clearFixtureUniverse` when blanked). Show the currently-applied universe (from the model) vs the in-form value so the user knows whether a separate apply is needed.
3. **Channels** — `ChannelListEditor` subview: per-row `name` text field, `offset` stepper, `kind` picker, delete button; "Add channel" button below the list.
4. **Patterns** — `PatternListEditor` subview: each row a disclosure-style nested editor (`PatternRowEditor`) with name, fade timings, value list. **`PatternValueEditor` (the key UX bit):**
   - If `fixture.type == .light` and channels matching `kind == .colorRed/.colorGreen/.colorBlue` exist, show a `ColorPicker` at the top. On change, write the RGB components into matching pattern values (creating them if missing); separate slider for any `master_dimmer`/`color_white` channel.
   - **Below that, always** show every channel as a raw `Slider`(0–255) + numeric `TextField` row so the user can hand-tweak any value (matches the slider+text pattern in `InterfaceSettings.swift:122-136`).
   - Trigger button per pattern: "Fire" (no body) and "Fire for ___ ms" (with `stop_after_ms`) — both call `triggerPattern`. Disabled if the fixture has no assigned universe (with explanatory tooltip).
5. **Bindings** — `BindingListEditor` subview: per-row a creature picker (drop-down from `@Query CreatureModel`, plus a "missing/manual UUID" affordance for cases where the creature isn't local), `on_reason` picker (`ActivityReason?` — nil = "any"), `on_state` picker (`ActivityState?` — nil = "any"), pattern picker (scoped to *this* fixture's patterns).

Toolbar buttons: **Validate** (calls `validateFixture(rawJson:)` and surfaces both `error_messages` and `missing_creature_ids` warnings via `.alert`), **Save** (validate locally + remote, then `upsertFixture`), and **Delete** (only for non-new). Use the `ServerError.detailedMessage` + `.alert()` pattern called out in CLAUDE.md "Server Communication Best Practices". Show a transient "Saving…" overlay via `.glassEffect(.regular.tint(.green), in: .capsule)` like `AnimationTable.swift:147-155`.

### 6 — Track ↔ fixture wiring (data layer only this round)

We need the Common-package field so animations *can* target fixtures, but the existing record/playback UI in `AnimationEditor.swift` is joystick-driven for creatures and doesn't naturally extend to fixtures. For this PR:
- Add `fixtureId` to `Track` (covered in §1).
- Confirm existing Animation playback paths don't break (round-trip tests already cover this).
- Leave authoring of fixture-targeted tracks for a follow-up. (No UI changes to `AnimationEditor.swift`.)

### 7 — CreatureCLI

Add a new top-level `Fixtures` subcommand mirroring `Common/Sources/CreatureCLI/creaturesCommand.swift` patterns (every subcommand uses `tracedRun(...)` and surfaces `ServerError.detailedMessage(from:)` on failure).

New file `Common/Sources/CreatureCLI/fixturesCommand.swift`. Subcommands:

| Subcommand | Mirrors | Notes |
|---|---|---|
| `fixtures list` | `creatures list` | Calls `getAllFixtures`, prints a table: Name, ID, Type, Universe (or `—`), Channel Offset, Channel Count. |
| `fixtures detail <id>` | `creatures detail` | Calls `getFixture`, prints human-readable summary including channels, patterns, bindings. New helper `CreatureDetailFormatter`-style `fixtureDetails(_:)` (either co-located in `fixturesCommand.swift` or a new `FixtureDetailFormatter.swift` if it grows). |
| `fixtures validate <file>` | `creatures validate` | Reads file from disk, calls `validateFixture(rawJson:)`, prints `valid`, `missing_creature_ids` (warnings), `error_messages`. Same file-existence guards as `Creatures.Validate`. |
| `fixtures upsert <file>` | (new — closest analog: `creatures validate` for file I/O) | Reads JSON file, calls `upsertFixture` (no need to decode locally first — but parse just enough to confirm it's valid JSON and extract the `id` for nicer success output). |
| `fixtures delete <id>` | (new) | Calls `deleteFixture(id:)`. Prints the server's status message. |
| `fixtures universe <id> --set N` / `fixtures universe <id> --clear` | `creatures idle` (the mutually-exclusive flag pattern) | One of `--set` / `--clear` required; rejects both/neither like `Idle.run()` does for `--enable`/`--disable`. |
| `fixtures trigger <fixtureId> <patternId> [--stop-after-ms N]` | (new) | Calls `triggerPattern(...)`. Validates `--stop-after-ms` is in `(0, 600000]` client-side to give nicer errors before the round trip (the server enforces the same range). |

Wire into `Common/Sources/CreatureCLI/top.swift:39-42` by adding `Fixtures.self` to the `subcommands:` array (alphabetical position: between `Debug` and `Metrics`).

Bump `CreatureCLI`'s `version:` string (currently `"2.20.1"` at `top.swift:38`) — pick the next appropriate semver based on whatever the project's current tagged version is when this lands.

Bash completions auto-regenerate via `create_completions.sh` — no manual completion edits needed.

## Verification

1. **Build & test the package**:
   ```
   cd Common && swift build
   cd Common && swift test
   ```
   All new tests pass; existing tests stay green.
2. **Build the apps**: `xcodebuild -project "Creature Console.xcodeproj" -scheme "Creature Console" -destination "platform=macOS"` (and one iOS destination). Confirm tvOS still builds with the new model registration.
3. **swift-format** every modified/new file per CLAUDE.md ("Run swift-format on any files you modify").
4. **CLI smoke**: `cd Common && swift run creature-cli fixtures list` — connects to prod and prints the table. Then `swift run creature-cli fixtures upsert path/to/stage-left-spot.json`, `swift run creature-cli fixtures universe <id> --set 1`, `swift run creature-cli fixtures trigger <id> <patternId> --stop-after-ms 1500`, `swift run creature-cli fixtures detail <id>`, `swift run creature-cli fixtures delete <id>`. Regenerate completions: `./create_completions.sh`.
5. **End-to-end against prod** (`server.prod.chirpchirp.dev`):
   1. Launch macOS app; confirm "Fixtures" section appears in the sidebar and lists `getAllFixtures` results.
   2. Create the spec's `"Stage Left Spot"` fixture from `FixtureEditor`; hit Validate — expect green. Save — expect server confirmation.
   3. Assign universe `1` via the inline universe control; restart the app; confirm universe survives (the persistence check called out in the server spec).
   4. Add a "Red Glow" pattern; hit Fire — observe DMX via sACNView/OLA or server `DEBUG_DMX_SENDER` log.
   5. Add a binding `{Beaky, ad_hoc, running, red-glow}`; trigger an ad-hoc speech for Beaky; observe fade-in → hold → fade-out.
   6. Delete the fixture; confirm it disappears from both the table and the server `GET /fixture` list.
   7. From a second running client (or via `curl` / the CLI), upsert a fixture; confirm the websocket cache-invalidation message rebuilds the SwiftData cache and the table updates without a manual refresh.
6. **Light-editor sanity**: with a `light`-type fixture, change the `ColorPicker` and confirm the raw RGB sliders below update to match (and vice versa).

## Files Touched (Summary)

**New (Common package)**: 12 model/DTO files under `Common/Sources/Common/Model/DmxFixture/` and `Common/Sources/Common/Model/DTO/`; `FixtureMethods.swift`; 2 test files.

**Modified (Common package)**: `Types.swift`, `CacheInvalidation.swift`, `Track.swift`.

**New (GUI app)**: `DmxFixtureModel.swift`, `DmxFixtureImporter.swift`, and ~6 view files under `Sources/Creature Console/View/Fixtures/` (`FixturesTable.swift`, `FixtureEditor.swift`, `ChannelListEditor.swift`, `PatternListEditor.swift`, `PatternValueEditor.swift`, `BindingListEditor.swift`).

**Modified (GUI app)**: `CreatureConsole.swift`, `Creature TV/Creature_TVApp.swift`, `View/AppBootstrapper.swift`, `Controller/Server/CacheInvalidationProcessor.swift`, `View/TopContentView.swift`.

**New (CLI)**: `Common/Sources/CreatureCLI/fixturesCommand.swift`.

**Modified (CLI)**: `Common/Sources/CreatureCLI/top.swift` (subcommands list + version bump).
