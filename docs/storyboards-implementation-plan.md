# Storyboards — Implementation Plan

> Client-side implementation plan for the Storyboards feature in Creature Console. The matching
> server-side work is specified separately in `storyboard-server-contract.md` and built in parallel.

## Context

The "Live Magic / Live Console" section works but has never felt right, and we want much more from it.
**Storyboards** reimagines live performance as a HyperCard-style surface: a named *card* holding
free-form *tiles* (programmable buttons), each wired to existing app functionality. The operator opens
a storyboard **full-screen on an iPhone/iPad** (or Mac) and taps tiles to make characters do things —
discreetly, in the background, like an Imagineer with a Steamdeck — while bystanders interact with the
animatronics. Each event gets its own storyboard, prepped ahead of time.

**Client-driven**: the server only stores the storyboard JSON. The console defines the entire shape.
Storyboards are created/edited on any device, saved to the server, cached locally in SwiftData, and
synced across devices (author on Mac, perform on iPhone). Mirrors the DialogScript feature end-to-end.

**Locked decisions**
- **Layout:** free-form drag with **relative (0–1) coordinates** for position *and* size — a card
  scales proportionally Mac→iPhone.
- **Build scope:** client only here; server CRUD per `storyboard-server-contract.md`.
- **Input:** **touch only** (haptic + brief visual confirmation). The joystick is reserved entirely
  for **live control** (driving a streamed creature); it never fires tiles. A tile can *toggle* live
  control; once streaming, the joystick drives that creature while tiles stay touch-operated.
- **Actions:** all v1 action types (below).
- **Universe:** a tile's universe is optional, defaulting to "follow the active universe"
  (`UserDefaults["activeUniverse"]`), with an optional per-tile override.
- **tvOS:** no Storyboard UI; the shared SwiftData model still compiles into the TV target.

## Concepts & UX
- **Storyboard**: `{ id, title, notes, tiles[], created_at, updated_at }`.
- **Tile**: button at relative `x/y/width/height` (0–1), with `label`, `sfSymbol`, `tintColorHex`,
  `action`. `id` is sent over the wire (identity is part of the document).
- **Edit mode** (macOS/iOS): free-form canvas — drag to move, corner handle to resize, tap to select
  → inspector to style + program the action (pickers backed by cached data). Save = create/update.
- **Perform mode** (macOS/iOS): full-screen, distraction-free. Tap → run → haptic + ~0.4s flash.
  Deliberate long-press exit so a stray tap never ends the show.

## 1. Data model — `Common/Sources/Common/Model/Storyboard/`
- `Types.swift`: `public typealias StoryboardIdentifier = UUID`.
- **`StoryboardAction.swift`** — `enum: Codable, Equatable, Hashable, Sendable`, encoded as a tagged
  object `{ "type": "<discriminator>", …snake_case params }`. Cases:

  | case | `type` | runs |
  |---|---|---|
  | `playAnimation(animationId, universe?, interrupt, resumePlaylist)` | `play_animation` | `playStoredAnimation`/`interruptWithAnimation` |
  | `adHocSpeech(creatureId, resumePlaylist)` | `ad_hoc_speech` | prompt → `createAdHocSpeechAnimation` |
  | `liveControl(creatureId, universe?)` | `live_control` | **toggle** stream to creature (green while live) |
  | `startPlaylist(playlistId, universe?)` | `start_playlist` | `startPlayingPlaylist` |
  | `stopPlaylist(universe?)` | `stop_playlist` | `stopPlayingPlaylist` |
  | `playSound(fileName)` | `play_sound` | `playSound` |
  | `renderDialog(scriptId)` | `render_dialog` | `renderDialog(.fromScript(…, .adhoc, autoplay:true))` |
  | `fixtureOn(fixtureId)` | `fixture_on` | `setFixtureLive` → channels full |
  | `fixtureOff(fixtureId)` | `fixture_off` | `setFixtureLive` → channels 0 |
  | `fixturePattern(fixtureId, patternId, stopAfterMs?)` | `fixture_pattern` | `triggerFixturePattern` |
  | `fixtureDetails(fixtureId)` | `fixture_details` | opens a control sheet (On/Off/Pattern/Color) |
  | `unknown(type, raw: [String: JSONValue])` | (verbatim) | friendly "update the app" failure |

  **Forward-compatible Codable:** `init(from:)` reads `type`, switches, `decodeIfPresent`s params with
  defaults; the `default:` branch decodes the whole object into `[String: JSONValue]` → `.unknown`,
  re-encoded verbatim so an old client round-trips a future type. UUID params encode lowercased.
  Universe params are `Int?` (nil ⇒ follow active universe). A small `JSONValue` any-JSON box backs
  `.unknown`.
- **`StoryboardTile.swift`**: `id: UUID` (on the wire), `x/y/width/height: Double` (0–1, clamped on
  decode), `label`, `sfSymbol` (`sf_symbol`), `tintColorHex` (`tint_color_hex`), `action`. Touch-only
  (no joystick binding).
- **`Storyboard.swift`**: `id/title/notes/tiles/createdAt/updatedAt` — custom `init(from:)`/`encode(to:)`
  like `DialogScript` (id lowercased; `decodeIfPresent` defaults; `Int64?` epoch-ms; date helpers).
  `UpsertStoryboardRequest` (title/notes/tiles only) + `newEmpty()`/`mock()`.
- **`Model/DTO/StoryboardListDTO.swift`**: `{ count: Int32, items: [Storyboard] }`.

## 2. Server methods — `Common/.../RESTful/StoryboardMethods.swift`
Mirror `DialogMethods.swift` at `/api/v1/storyboard`: `listStoryboards`, `getStoryboard(id:)`,
`createStoryboard(_:)` (POST upsert → 201), `updateStoryboard(_:)` (PUT /{id} → 200),
`deleteStoryboard(id:)` (→ StatusDTO.message). Add `CacheType.storyboardList = "storyboard-list"` +
the arm in `DebugMethods.invalidateCache(for:)`.

## 3. Server contract
See `storyboard-server-contract.md` (written first; the source of truth for the parallel server work).

## 4. App data layer — `Sources/Creature Console/`
- `Model/Storyboard/StoryboardModel.swift` — `@Model`, `@Attribute(.unique) id: UUID`, **`tilesJSON:
  Data` blob** (not a `@Relationship`), `createdAtMillis/updatedAtMillis: Int64?`, `init(dto:)`/
  `toDTO()`, `tileCount`, date helpers.
- `Model/Storyboard/StoryboardImporter.swift` — `@ModelActor` `upsertBatch`/`deleteAllExcept`.
- Register `StoryboardModel.self` in `modelTypes` in BOTH `CreatureConsole.swift` and
  `Creature TV/Creature_TVApp.swift`.
- `CacheInvalidationProcessor.swift` — `loadStoryboardsTask`, `.storyboardList` case,
  `rebuildStoryboardCache(Async)`, line in `rebuildAllCaches()`.
- `View/AppBootstrapper.swift` — `importStoryboardsIntoSwiftData()` in both `imports` arrays.

## 5. Shared action facades + thin runner (DRY)
**A tile must not re-implement how a feature is triggered.** Each capability lives in one facade,
called by both its existing detail screen and the storyboard runner; refactor the existing screen onto
it (single source of truth). Facades:
- **Live control** — `CreatureManager.toggleStreaming(to:universe:)` (extract from
  `CreatureDetail.toggleStreaming()`; refactor CreatureDetail onto it). Green "is-live" derives from
  `CreatureManager.streamingCreature` both screens observe.
- **Ad-hoc speech** — `AdHocSpeechService` (extract from `LiveMagicViewModel`); shared prompt view.
- **Animation play/interrupt** — shared universe/AppState helper; server methods are the single impl.
- **Fixtures** — `FixtureControlService` (on/off via `setFixtureLive`, color→RGB factored from
  `PatternValueEditor`, `triggerFixturePattern`); used by `FixtureEditor` and the runner.
- **Playlist/sound/dialog** — server client methods are the single impl; runner calls directly.

**Thin runner** `Controller/Storyboard/StoryboardActionRunner.swift` (`@MainActor`, owned by the
perform view): `run(_ action:promptText:) async -> RunOutcome` dispatches to facades, resolves
universe (tile override else active), returns `.success`/`.failure(message)`/`.needsPrompt`/
`.presentFixtureSheet(fixtureId)`. No trigger logic of its own.

*Fixture on/off caveat:* `setFixtureLive` holds ≤10 min then blacks out; hold at max + re-fire on tap.
A stay-on-all-show fixture needs a server-side persistent-on (open item, not blocking).

## 6. Editor UI — `View/Storyboard/` (`#if os(iOS) || os(macOS)`)
- `StoryboardTable.swift` — mirrors `DialogScriptTable` (@Query sorted by `updatedAtMillis`, context
  menu incl. Perform, delete-with-confirm).
- `StoryboardEditor.swift` — free-form canvas in `GeometryReader`; center-based `.position` +
  `.frame` from 0–1 fractions; drag-move and corner-resize write clamped fractions (min ≈ 0.08).
  Inspector (pane on macOS / sheet on iOS): label, SF-symbol, `ColorPicker`(hex), action-type picker,
  per-case param pickers backed by `@Query` of creatures/animations/playlists/sounds/fixtures/dialogs
  (+ optional universe override). Save → create/update → replace original → `rebuildStoryboardCache`.

## 7. Perform mode — `View/Storyboard/StoryboardPerformView.swift`
`.fullScreenCover`, distraction-free. Tiles positioned by relative math (buttons), `.glassEffect`.
Tap → `UIImpactFeedbackGenerator(.medium)` (macOS no-op) + `runner.run` → ~0.4s green/red flash; fail
→ toast. `ad_hoc_speech` → shared prompt sheet. `live_control` tile **turns green while its creature
is streamed** (mirrors `CreatureDetail`). `fixture_details` → fixture control sheet reusing
`FixtureEditor`'s `LiveControlPanel`/`PatternValueEditor`. **Deliberate exit:** low-contrast corner,
~0.8s long-press.

## 8. Tests — `Common/Tests/CommonTests/`
`StoryboardTests.swift` + `StoryboardListDTOTests.swift`: server-shape decode (snake_case, epoch-ms,
lowercased uuid); full round-trip preserving relative coords; one `@Test` per action case (type +
snake_case keys, lowercased `script_id`); **forward-compat** unknown-type round-trip; tile clamp; list
DTO; `newEmpty()` invariants.

## 9. Ordering / risks / verification
**Phasing:** (0) write the two docs; (1) Common model + tests → `swift test`; (2) app data layer +
both `modelTypes` + cache/bootstrap; (3) extract facades + refactor existing screens (verify they
still behave); (4) editor UI + sidebar section; (5) thin runner + perform mode; (6) polish.

**Risks:** `.unknown` round-trip fidelity (guarded by the forward-compat test); SwiftUI `.position` is
center-based (handle the +size/2 offset); schema change wipes the disposable cache on both targets
(TV won't compile until its `modelTypes` includes `StoryboardModel`); with server endpoints absent,
all calls fail gracefully to cached data/logged failures (Save errors until the server ships); fixture
on/off hold ≤10 min.

**Verification:** `cd Common && swift test`; build macOS + iOS + Creature TV; `swift-format` every
touched file. End-to-end once the server exists: author on Mac → invalidate → appears on iPhone →
Perform → taps fire with haptic/confirmation; green live state tracks the streamed creature; exit
works. (April runs the app from Xcode.)
