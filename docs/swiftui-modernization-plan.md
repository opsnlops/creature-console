# SwiftUI / Swift 6 / Liquid Glass Modernization Plan

*Audit date: July 21, 2026 (v2.39.0). Four parallel audits: Liquid Glass adoption, state
management, Swift 6 concurrency, and view structure/idioms, across
`Sources/Creature Console/` and `Creature TV/`.*

## Where the app stands

The good news first — several things are already exemplary and should be treated as the
canonical patterns:

- **`BottomStatusToolbarContent` / `BottomToolBarView`** — `GlassEffectContainer` wrapping
  tinted, interactive glass dots/capsules with `glassEffectUnion` so they morph as a cluster.
  This is the flagship Liquid Glass pattern; everything else should look like this.
- **Settings** (`InterfaceSettings`, `NetworkSettings`, `AdvancedSettings`, `JoystickSettings`,
  `DebugSettings`) — fully migrated to glass cards.
- **`CreatureDetail`'s glass toolbar row**, **`JoystickDebugView`**, **Storyboard tiles** —
  good conditional-tint interactive glass.
- No custom toolbar/nav backgrounds anywhere; system chrome gets Liquid Glass for free.
- No deprecated `onChange` signatures, no `UIScreen`, no `@EnvironmentObject`/`@Published`
  remnants, ~42 `@AppStorage` uses, healthy `@Query`/SwiftData usage overall.
- Shared facades already exist and are good: `ErrorAlert`/`.errorAlert`, `ProcessingOverlayView`,
  `.watchJob`, `.bottomToolbarInset`. The problem is incomplete adoption, not missing design.

The big themes to fix:

1. **Zero Observation-framework adoption.** 14 `ObservableObject`s, `@StateObject`s, and
   hand-rolled Combine remain; no `@Observable` anywhere.
2. **AsyncStream mirror boilerplate.** ~24 hand-written `for await` loops across 13 views
   mirror actor state into local `@State`; the AppState + StatusLights + WebSocket triad is
   copy-pasted verbatim in three chrome views.
3. **A few real concurrency bugs** hiding behind `nonisolated(unsafe)` / `@unchecked Sendable`.
4. **Liquid Glass is ~70% adopted** — Playlists, tvOS, sACN monitor, and the recording
   coordinator are still on `.thinMaterial`/`.ultraThinMaterial`/flat fills.
5. **Facade holdouts + duplication** — 26 files still hand-roll the alert triple, 7 copies of
   the pasteboard `#if os` block, 6 hand-rolled status banners, near-duplicate RecordTrack views.

---

## Phase 0 — Concurrency correctness (do first; real bugs)

| # | Fix | Where |
|---|-----|-------|
| 0.1 | `CacheInvalidationProcessor` holds seven `static nonisolated(unsafe) var` task handles mutated from the WebSocket pipeline — genuine data race (two invalidations, or invalidation vs. cancel-all, can collide). Convert the type to an `actor` owning the handles. | `Controller/Server/CacheInvalidationProcessor.swift:13-19,91-99,430-436` |
| 0.2 | `AprilsCreatureWorkshopJoystick.stateUpdates` has a **no-op `onTermination`** — every departed subscriber leaks its continuation forever. Restore removal via `Task { await self.removeSubscriber(id) }` (the pattern `CreatureHealthCache` uses). | `Model/Joystick/AprilsCreatureWorkshopJoystick.swift:84,100-103` |
| 0.3 | Non-`Sendable` joystick classes (`AprilsCreatureWorkshopJoystick`, `SixAxisJoystick` with its `@unchecked Sendable`) are mutated from both the `JoystickManager` actor and IOKit/GameController callbacks. Re-isolate: make the joystick types actors or funnel all mutation through `JoystickManager`. Also audit `SendableGCController` (`JoystickHandler.swift:10`) — `GCController` is main-thread-affined. | `Model/Joystick/*`, `Controller/Joystick/JoystickManager.swift` |
| 0.4 | `AppState.setCurrentActivity` evaluates `Thread.callStackSymbols` on every state change (stack symbolication on a hot path). Remove it; trim the double `.info` logging. | `Controller/AppState.swift:110` |
| 0.5 | `EventLoop` spawns two unstructured `Task {}` per 50 Hz tick (poll + creature tick) — unbounded queueing if an actor backs up. Await them in the loop body; consider replacing the `DispatchSource` timer with a structured `ContinuousClock` loop. Fix the stale doc comment. | `Controller/Events/EventLoop.swift:82-89,124-134` |
| 0.6 | Fixed `Task.sleep(4s)` spinner after server stop calls instead of keying off the actual result (no-delays rule). | `View/Creatures/CreatureDetail.swift:258`, `Creature TV/View/CreatureDetailTV.swift:125` |
| 0.7 | View-side `DispatchQueue.main.async` / `.asyncAfter` (uncancellable timers) → structured `Task`/`Task.sleep` or plain assignment. | `NetworkSettingsView.swift:135`, `LiveMagicPromptSheet.swift:89`, `CreateNewCreatureSoundView.swift:158,208,234`, `CreatureDetailTV.swift:116` |
| 0.8 | `JobStatusStore.events()` registers its continuation one actor-hop late — events can be lost in the window. Make registration synchronous (actor-isolated `events()`). | `Model/Jobs/JobStatusStore.swift:59-63` |
| 0.9 | **Deferred to its own PR** — verified: `Common.Animation` and `Common.Playlist` are `final class` with `var` fields behind `@unchecked Sendable`, and the app mutates them in place (rename flow, editor view model), so the annotation is genuinely unsound. The fix is converting both to structs, which ripples through Common, the CLI, and the editor view model — too big to ride along in Phase 0. | `Common/Sources/Common/Model/…` |
| 0.10 | Nested `NavigationStack`: `AnimationEditor` wrapped its body in its own stack while every presentation site pushes it onto an existing stack (and it pushes a third level for RecordTrack). Fixed by removing the editor's stack. (`StoryboardEditor` was a false positive — its inner stack is inside a `.sheet`, which is correct.) | `AnimationEditor.swift:74`, `AnimationTable.swift:355` |

## Phase 1 — Mechanical modernization sweep (low risk, wide)

- **Deprecated `Alert` value type → `.errorAlert` facade** (14 files with `Alert(...)`; part of
  the broader 26-file alert-triple migration in Phase 2): `BottomToolBarView`, `RootView`,
  `TopContentView`, `SoundDataImporter`, `TrackViewer`, `RecordTrack`, `AnimationTable`,
  `CategoryList`, `AnimationRecordingCoordinator`, `RecordTrackForSession`,
  `CreateNewCreatureSoundView`, `SoundFileListView`, `LiveMagicView`, `CreatureDetail`.
- **`NavigationView` → `NavigationStack`** (5): `PlaylistDetail:339`,
  `RecordTrackForSession:390`, `AnimationRecordingCoordinator:290,479`, `InputTable:341`.
- **`PreviewProvider` → `#Preview`** (18 files — list in the state-management audit).
- **`.foregroundColor` → `.foregroundStyle`** (49 uses; concentrated in `InputTable`,
  `SensorData`, `AnimationRecordingCoordinator`, `RecordTrackForSession`).
- **`.cornerRadius` → `.clipShape(.rect(cornerRadius:))`** (14 uses).
- **Redundant `await MainActor.run` sweep** (~150 sites): SwiftUI views are `@MainActor`;
  `Task {}` launched from them inherits it. Keep only the real hops in actor code
  (`SwiftMessageProcessor`, `CreatureManager`, `LipSyncUtilities`), ideally by marking target
  methods `@MainActor` instead. Mark `.watchJob`'s callbacks `@MainActor` and drop its per-event hop.
- **Dead UI**: `AnimationTable` "Play Sound File" `print` stub (implement or remove),
  `PlaylistsTable:120` no-op `Button("Shit") {}`, `print("DEBUG:…")` in `EditPlaylistSheet`,
  stray `print`s → logger.
- **Pasteboard helper**: one `Pasteboard.copy(_:)` in `View/Shared/`, deleting 7 identical
  `#if os` blocks and ~8 now-unneeded UIKit/AppKit imports.

## Phase 2 — DRY facades (finish what's started)

- **`.statusBanner(...)` modifier** (auto-dismiss + generation counter, glass capsule, tint
  parameter) replacing 6 hand-rolled implementations in `AnimationTable`, `AnimationEditor`,
  `StoryboardEditor`, `DialogScriptEditor`, `StoryboardPerformView`, `SoundDataImporter`.
- **Finish `.errorAlert` adoption** across all 26 holdout files; collapse the four-field
  success/error bool+string pairs (`PlaylistsTable`, `StoryboardTable`, `DialogScriptTable`,
  `FixturesTable`) into one presentation value. Success confirmations should stop flowing
  through error-alert plumbing (e.g. "Animation Renamed" currently rides `showErrorAlert`).
- **Broaden `ProcessingOverlayView`** to the hand-rolled progress overlays
  (`AnimationRecordingCoordinator`, `RecordTrack`, `RecordTrackForSession`, `PlaylistsTable`,
  `DebugSettings`).
- Platform helpers for the recurring `#if os` frame/full-screen branches (191 `#if os` in 60
  view files; pasteboard extraction plus these helpers absorbs the bulk).

## Phase 3 — Observation migration (the architectural one)

- **`ConsoleStore`** (or similar): one `@MainActor @Observable` object that subscribes once to
  `AppState.stateUpdates`, `StatusLightsManager`, WebSocket state, and joystick streams, injected
  via `.environment(...)`. Views read plain properties. Deletes ~24 `for await` mirror loops and
  their `@State` mirrors (the triad in `TopContentView`/`BottomStatusToolbarContent`/
  `BottomToolBarView` is verbatim-duplicated today).
- **`ObservableObject` → `@Observable`** for all 14 conformances; `@StateObject` → `@State`,
  `@ObservedObject` → let/`@Bindable`. Fixes the `@ObservedObject var x = Singleton.shared`
  anti-pattern (`BottomToolBarView:8`, `CreatureDetail:23`).
- **Remove Combine** from UI/model code (`CreatureHealthCache`, the three joystick files);
  `SixAxisJoystick`'s hand-rolled `ObservableObjectPublisher` plumbing goes away with
  `@Observable`.
- **Singleton DI**: views stop holding `CreatureServerClient.shared` etc. as stored `let`s
  (~25 view types today); inject via `@Environment`. The injectable-default pattern in
  `FixtureControlService`/`LiveMagicViewModel` is the model.
- Replace getter-per-property actor APIs with snapshot reads; fix inline
  `SwiftDataStore.shared.container()` where `modelContext` is already injected
  (`PlaylistsTable:240,283`, `SACNUniverseMonitorView:847`); move `modelContext.save()`
  mutations out of view bodies (`AnimationTable:534,602`).

## Phase 4 — Liquid Glass completion (the pretty one)

Priority order by visibility:

1. **iOS status lights**: wrap `iOSStatusLightsView` (`TopContentView:319-379`) in a
   `GlassEffectContainer` so the cluster morphs like the macOS one.
2. **tvOS**: soundboard + animation-trigger cards and refresh overlays off
   `.ultraThinMaterial` onto tinted glass (`TVSoundboardView:70,142`,
   `TVAnimationTriggerView:73,174`, `TVUserFeedback:27`, `CreatureDetailTV:35`); unify tvOS
   toasts onto the tinted-glass-capsule banner convention.
3. **Playlists**: all panels/bars off `.thinMaterial` (`PlaylistsTable:429,479,508,688`,
   `PlaylistDetail:52,63,112,353`, `CreatePlaylistView:40,66`).
4. **sACN monitor** panels (`SACNUniverseMonitorView:446,707`).
5. **Recording coordinator** panels off opaque `systemBackground`/`systemGray6`
   (`AnimationRecordingCoordinator:101,343,426,466`).
6. **`.glassProminent`/`.glass`** for in-content primary CTAs (tvOS play/interrupt, Dialog
   render, LiveMagic generate, Playlist save — full list in the glass audit).
7. **`.interactive()`** on tappable glass (Fixtures editors, Storyboard inspector,
   `DialogRerenderButton`, `AnimationEditor` panels).
8. Misc flat chrome: StoryboardEditor black canvas backdrop + white circle chip, DialogScriptEditor
   field panel, red live-status capsules → tinted glass; delete the fake `LiquidGlass` helper
   view (`InterfaceSettings:273`).

## Phase 5 — Structure & decomposition

- Split `SACNUniverseMonitorView.swift` (1,482 lines: view model + raw NW sockets + canvas
  renderer + views → 4+ files; networking does not belong under `View/`).
- Decompose `AnimationTable.swift` (1,116 lines, 31 `@State`, 7 task handles): extract context
  menu, `RenameAnimationSheet`, `FilmingCountdownOverlay`, a lip-sync job controller.
- Merge/extract the near-duplicate `RecordTrack` ↔ `RecordTrackForSession` pair (411/401 lines).
- One-type-per-file splits: `PlaylistsTable` (6 types), `AnimationRecordingCoordinator`
  (6 types), `AdHocAssetsView`, `PlaylistDetail`, `SensorData`, `CreatureDetail`.
- `AnyView` → `@ViewBuilder` (7 sites: `TopContentView`, `TrackViewer`, `TrackListingView`);
  consolidate TopContentView's duplicated `navigationDestination` registrations.
- Accessibility sweep: `.help`/labels for icon-only buttons (72 icon sites, ~15 `.help`s today).

## Out of scope / owner's call

- The joke alert strings ("Oooooh Shit" / "Fuck" / "Fiiiiiine" / "WTF?" / `Button("Shit")`) are
  catalogued in the structure audit. This is a personal app — keeping them is a legitimate
  choice; the only functional issue is the no-op button.
- Chart internals (`BarChart` flat fills) read fine as data-viz; not worth glassing.
- Table-cell zebra tints look intentional.

## Sequencing note

Phases 0–2 are independent of Phase 3 and safe to land as small PRs. Phase 4 (glass) is purely
visual and can proceed in parallel. Phase 3 is the big rewiring and should land as its own
series (store first, then view-by-view migration off the streams). Phase 5 last — decomposition
is easiest once alerts/banners/observation have already shrunk the files.
