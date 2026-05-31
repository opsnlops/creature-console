# Multi-Character Dialog & DialogScript — Implementation Plan

> Client-side implementation plan for Creature Console. Pairs with the server-side guide at
> `creature-server/docs/multichar-dialog-client.md` (server v3.15.0+).

## Context

We're adding a way to author **multi-character dialog scenes** to Creature Console. The
creature-server already does the heavy lifting: it sends a scene's "turns" to ElevenLabs'
Text-to-Dialogue API (so characters actually react to each other in one jointly-conditioned
render), slices the mixdown into per-creature tracks, runs lip-sync, and assembles a multi-track
Animation for the 17-channel show.

Two related concepts:

1. **DialogScript** — a saved, editable CRUD asset (`title`, `notes`, `turns[]`, server-managed
   `id`/`created_at`/`updated_at`). Each **turn** is `{ creature_id, text }`, where `text` may
   carry inline ElevenLabs tags like `[excited]`. This is show-prep: author a scene, tweak it
   tomorrow, re-render.
2. **Dialog render** — turns a script (or inline turns) into a multi-track Animation via an async
   server job. A preview flow lets the author **listen before rendering**, and export mono /
   17-channel WAVs for inspection in Audacity.

Goal: a slick GUI under a new **"Dialogs"** sidebar section, a CLI command group, and full parity
with the server's validation limits. The client does almost no audio work itself — it's a thin,
well-instrumented shell over the server API.

Server API base path: `/api/v1`. All JSON over HTTP except the WAV export endpoints (raw bytes).
Render is async over the **existing** websocket job framework (`job-progress` / `job-complete`,
`job_type: "dialog"`). Script CRUD broadcasts a `cache-invalidate` with
`cache_type: "dialog-script-list"`.

---

## Phase 1 — Common package (models, DTOs, enums, server methods)

All of `Common/Sources/Common/...`. Mirror existing shapes exactly (snake_case `CodingKeys`,
`Codable`/`Identifiable`/`Hashable`/`Equatable`/`Sendable`).

**Type alias** — `Types.swift`: add `public typealias DialogScriptIdentifier = String`.

**Models** — new `Model/Dialog/`:
- `DialogScript.swift` — structs `DialogScriptTurn` and `DialogScript` (mirror
  `Model/Animation/AnimationMetadata.swift` style).
  - `DialogScriptTurn`: `creatureId: CreatureIdentifier` (key `creature_id`), `text: String`,
    plus a client-only `id: UUID` for SwiftUI `ForEach`/`.onMove` that is **excluded from
    `CodingKeys`** (freshly minted in `init(from:)`, never sent/round-tripped).
  - `DialogScript`: `id`, `title`, `notes`, `turns: [DialogScriptTurn]`,
    `createdAt`/`updatedAt: Date?` (keys `created_at`/`updated_at`, `decodeIfPresent`). Full init
    + a "new" init that mints `UUID().uuidString.lowercased()` with empty turns; `mock()`.
- `DialogLimits.swift` — `enum DialogLimits` with `maxTurns=200`, `maxTurnText=4096`,
  `maxTitle=256`, `maxNotes=16384` (single source of truth for the editor + tests; matches server
  `DialogScript.h`).

**DTOs** — new files in `Model/DTO/` (mirror `AnimationMetadataListDTO`, `FixtureConfigValidationDTO`):
- `DialogScriptListDTO.swift` — `{ count: Int32, items: [DialogScript] }`.
- `DialogRequestDTO.swift` — `enum DialogPersistence: String { case adhoc, permanent }`; struct
  `DialogRequest: Encodable` with `turns: [DialogScriptTurn]?` **XOR** `scriptId`, `persistence`
  (required), `autoplay: Bool?`, `title: String?`, `generationId: UUID?`. Two convenience inits
  (`fromScript`, `fromTurns`); `encodeIfPresent` so only the populated XOR side is sent. **Reuse
  the existing `JobCreatedResponse`** (in `Jobs/JobModels.swift`) for the 202 body — don't add a
  new accepted-DTO.
- `DialogScriptValidationDTO.swift` — `{ valid, scriptId?, turnCount, missingCreatureIds[],
  errorMessages[] }` (snake_case keys). Always HTTP 200.
- `DialogPreviewDTO.swift`:
  - `DialogPreviewMetaRequest: Encodable` — `turns?` / `scriptId?`, `generationId: UUID?`,
    `regenerate: Bool?`.
  - `DialogPreviewMetaDTO: Decodable` — `cacheKey`, `generationId`, `cached`, `audioUrl`
    (relative, starts `/api/v1/...`), `audioFormat`, `sampleRate`, `durationSeconds`,
    `voiceSegments[]`, `forcedAlignmentWords[]`, `forcedAlignmentChars[]`, `forcedAlignmentLoss?`.
    Alignment/segment inner structs decode best-effort (not needed for the listen MVP; used later
    for a scrubber).
  - `DialogPreviewLookupDTO: Decodable` — `cacheKey`, `latestGenerationId`,
    `generations: [{ generationId, createdAt }]` (200, or 404 → `.notFound` at the method layer).

**Enum additions**:
- `Model/Jobs/JobModels.swift` — add `case dialog = "dialog"` to `JobType`; add result struct
  `DialogJobResult` (`animation_id`, `number_of_frames`, `milliseconds_per_frame`,
  `duration_seconds`, `persistence`, `autoplayed`) alongside `AdHocSpeechJobResult`.
- `Model/CacheInvalidation/CacheInvalidation.swift` — add `case dialogScriptList = "dialog-script-list"`.

**Server methods** — new `Controller/Server/RESTful/DialogMethods.swift` (mirror
`FixtureMethods.swift`/`PlaylistMethods.swift`; use `makeBaseURL(.http) + "/animation/dialog/..."`,
generic `fetchData`/`sendData`, `EmptyBody()` for DELETE):
```
listDialogScripts() -> Result<[DialogScript], ServerError>            // GET  /script → .items
getDialogScript(id:) -> Result<DialogScript, ServerError>            // GET  /script/{id}
createDialogScript(_:) -> Result<DialogScript, ServerError>          // POST /script (201)
updateDialogScript(_:) -> Result<DialogScript, ServerError>          // PUT  /script/{id} (200)
deleteDialogScript(id:) -> Result<String, ServerError>               // DELETE → StatusDTO.message
validateDialogScript(_:) -> Result<DialogScriptValidationDTO, …>     // POST /script/validate (200)
renderDialog(_:) -> Result<JobCreatedResponse, ServerError>          // POST /dialog (202)
dialogPreviewMeta(_:) -> Result<DialogPreviewMetaDTO, ServerError>   // POST /preview/meta
dialogPreviewLookup(_:) -> Result<DialogPreviewLookupDTO, ServerError> // POST /preview/lookup
dialogPreviewMultichannel(_:) -> Result<Data, ServerError>          // POST /preview/multichannel (raw WAV)
dialogPreviewAudioURL(cacheKey:filename:) -> Result<URL, ServerError>
makeAbsoluteURL(fromRelativePath:) -> URL?                          // host-root helper, see below
```

**URL footgun (resolve here):** `makeBaseURL(.http)` already appends `/api/v1`, but the preview
`audio_url` is a path that **also** starts with `/api/v1/...`. Add `makeAbsoluteURL(fromRelativePath:)`
that strips a trailing `/api/v1` from the base and appends the relative path. All other dialog
endpoints use `makeBaseURL(.http)` normally. Preview audio must be downloaded through
`createConfiguredURLRequest(for:)` (proxy/API-key/Host + W3C trace headers) — which
`AudioManager.prepareMonoPreview` already does. For `dialogPreviewMultichannel`, do a custom
`URLSession` call via `createConfiguredURLRequest` (no JSON decode; return `Data`).

If `CreatureServerClientProtocol` declares CRUD for other resources, add the dialog signatures there too.

---

## Phase 2 — App data layer (SwiftData, importer, cache, bootstrap, jobs)

All of `Sources/Creature Console/...`.

- **SwiftData model** — new `Model/Dialog/DialogScriptModel.swift` (mirror
  `Model/DmxFixture/DmxFixtureModel.swift`: store `turns` as a JSON-blob `Data`). Fields:
  `@Attribute(.unique) id`, `title`, `notes`, `turnsJSON: Data`, `createdAt: Date?`,
  `updatedAt: Date?`. Extension with `convenience init(dto:)`, `toDTO()` (best-effort encode/decode
  with `[]` fallback), and a derived `turnCount`.
- **Importer** — new `Model/Dialog/DialogScriptImporter.swift`: `@ModelActor actor` with
  `upsertBatch(_:)` + `deleteAllExcept(ids:)`, copied from
  `Model/Animation/AnimationMetadataImporter.swift`.
- **ModelContainer** — `CreatureConsole.swift` (~line 119): add `DialogScriptModel.self`.
- **Cache invalidation** — `Controller/Server/CacheInvalidationProcessor.swift`: add a
  `loadDialogScriptsTask` var, a `.dialogScriptList` switch case, `rebuildDialogScriptCache`/
  `rebuildDialogScriptCacheAsync` (mirror the animation pair; calls `listDialogScripts()` →
  `DialogScriptImporter`), and a line in `rebuildAllCaches()`.
- **Startup import** — `View/AppBootstrapper.swift`: add `importDialogScriptsIntoSwiftData()`
  (mirror `importAnimationsIntoSwiftData()`), wire it into the `async let` groups in
  `startIfNeeded()` **and** `refreshCachesAfterWake()`, and extend the results tuple +
  `handleImportResults` signature/cases (arity change — update all sites together).
- **Job result** — `Model/Jobs/JobStatusStore.swift`: add `dialogResult: DialogJobResult?` to
  `JobInfo`; set `nil` in the progress initializer; decode it in the completion path. No change in
  `JobStatusMessageProcessor`/`WebSocketMethods` — `dialog` jobs flow through automatically once
  `JobType.dialog` exists.

---

## Phase 3 — App UI (`Sources/Creature Console/View/Dialog/`, macOS/iOS)

New directory `View/Dialog/`. Editor mirrors `View/Fixtures/FixtureEditor.swift`; table mirrors
`View/Animation/AnimationTable.swift`; job observation mirrors `AnimationTable`'s
`JobStatusStore.shared.events()` subscription.

- **DialogScriptTable.swift** — `@Query(sort: \DialogScriptModel.updatedAt, order: .reverse)`;
  list of title · turn count · updated date. Row → `DialogScriptEditor(existing:)`. Delete
  (confirm) → `deleteDialogScript(id:)` then `rebuildDialogScriptCache(deleteStaleEntries: true)`.
- **DialogScriptEditorViewModel.swift** — `@MainActor ObservableObject`: `@Published script`,
  `validation`, `isSaving`/`isValidating`, alert state. **Debounced validation**: on each `script`
  change, cancel the prior `validateTask`, `Task.sleep(~400ms)`, then `validateDialogScript`;
  guard `Task.isCancelled` before publishing. `addTurn()`/`removeTurn(at:)`/`moveTurn(from:to:)`.
  `save()` → create vs update by whether the script has a server id, then rebuild cache. Enforce
  `DialogLimits`.
- **DialogScriptEditor.swift** — sectioned form: title (≤`maxTitle`), notes multiline
  (≤`maxNotes`); turns section = `ForEach(script.turns)` rows of creature `Picker` (bound to
  `turn.creatureId`, from `@Query [CreatureModel]`) + multiline `TextEditor` (≤`maxTurnText`, live
  char count), `.onMove` reorder, delete, "Add Turn" (disabled at `maxTurns`). Validation banner:
  `error_messages` (red) + `missing_creature_ids` (orange). Toolbar: Validate / Save / Delete.
  Inits `init(createNew:)` / `init(existing:)`. Reveal render + preview panels once the script has
  a server id.
- **DialogRenderPanel.swift** — persistence `Picker`, autoplay `Toggle`, optional title. "Render"
  → build `DialogRequest` (`fromScript` if saved else `fromTurns`, carrying chosen `generationId`)
  → `renderDialog` → capture `jobId` → subscribe to `JobStatusStore.shared.events()` filtered by
  `jobId`, show progress, on `.completed` read `dialogResult.animationId` → navigate to the
  rendered animation; on `.failed` alert. Resilience: on timeout, `rebuildAnimationCache(...)` and
  point the user at the Animations list (no job-polling endpoint).
- **DialogPreviewPanel.swift ("Listen")** — "Preview" → `dialogPreviewMeta` → absolute URL via
  `makeAbsoluteURL(fromRelativePath: meta.audioUrl)` → `AudioManager.shared.prepareMonoPreview` →
  play. Duration + cached badge. **Take picker**: `dialogPreviewLookup` lists `generations`
  newest-first; selecting sets `generationId`; "Regenerate" sets `regenerate: true`.
- **WAV export (for Audacity)** — buttons in the preview panel: *Export mono WAV* (download
  `audio_url` bytes through `createConfiguredURLRequest`) and *Export 17-channel WAV*
  (`dialogPreviewMultichannel` → `Data`). Save via macOS `NSSavePanel`/`.fileExporter`, iOS share
  sheet; reuse `View/Settings/DiagnosticReporter.swift` file-writing where applicable.
- **Provenance** (rendered animation) — if metadata carries `source_script_id`, show "Edit this
  script" → `getDialogScript(id:)`; on 200 open `DialogScriptEditor(existing:)`, on 404 fall back
  to the read-only `source_script_turns` snapshot. Decode via a small `DialogProvenance` struct from
  the animation metadata JSON. Lower-priority polish.
- **Sidebar** — `View/TopContentView.swift`: a new `Section("Dialogs")` directly **below**
  `Section("Animations")` (inside the existing `#if os(iOS) || os(macOS)` block), with links →
  `DialogScriptTable()` ("List All", `text.bubble`) and `DialogScriptEditor(createNew: true)`
  ("Create New", `plus.bubble`).

---

## Phase 4 — CLI (`Common/Sources/CreatureCLI/`)

- New `dialogCommand.swift` — `struct Dialog: AsyncParsableCommand` (mirror `fixturesCommand.swift`,
  `@OptionGroup() var globalOptions`, `tracedRun`, `printTable`,
  `failWithMessage(ServerError.detailedMessage(from:))`, `readJsonFile(at:)`). Subcommands:
  - `List` → table (Title · ID · Turns · Updated).
  - `Detail <id>` → `getDialogScript`.
  - `Validate <path>` → decode → `validateDialogScript`; print valid/turn_count/warnings/errors.
  - `Upsert <path>` → id empty → `createDialogScript` else `updateDialogScript`.
  - `Delete <id>` → `deleteDialogScript`.
  - `Render` → `--script-id` / `--input-path` XOR, `--persistence` (default adhoc), `--autoplay`,
    `--title` → `renderDialog` → print `job_id` (watch via `websocket` / `animations list`).
  - `ExportMono` / `ExportMultichannel` `<--script-id|--input-path> --output <path>` → write WAV.
- `top.swift` — add `Dialog.self` to `subcommands`; run `./create_completions.sh`. Bump CLI
  `version` and create a matching git tag at commit time.

---

## Phase 5 — Tests (Swift Testing, `Common/Tests/CommonTests/`)

Mirror the existing `*ListDTOTests`/`JobModelsTests` style (`import Testing`, `@Suite`, `@Test`,
`#expect`, `.iso8601` decoder). New files:
- `DialogScriptTests.swift` — snake_case round-trip; assert `DialogScriptTurn.id` is **not** in
  encoded JSON and is freshly minted on decode; `mock()`.
- `DialogScriptListDTOTests.swift` — count/items, empty array, missing-key failure.
- `DialogRequestDTOTests.swift` — XOR encoding; `persistence` always present; `generation_id` UUID.
- `DialogScriptValidationDTOTests.swift` — decode always-200 body incl. soft warnings.
- `DialogPreviewDTOTests.swift` — decode `preview/meta` + `preview/lookup` (incl. 404 path).
- `DialogJobModelsTests.swift` — `JobType.dialog` raw value; unknown→`.unknown`; `DialogJobResult`
  decodes from the job `result` JSON string.
- `DialogLimitsTests.swift` — assert 200 / 4096 / 256 / 16384.
- `CacheType.dialogScriptList` raw value `"dialog-script-list"`.

---

## Ordering & key risks

1. **Phase 1 first** (alias → models → DTOs → enum additions → `DialogMethods`).
2. Phase 2 depends on 1; Phase 3 on 1+2; Phase 4 on 1; Phase 5 on 1.
3. **Risks / care:** the `/api/v1` double-prefix on `audio_url` (use `makeAbsoluteURL`); the
   `handleImportResults` tuple-arity change in `AppBootstrapper` (update all sites together);
   cancel the debounced validate `Task` each keystroke; observe the `JobStatusStore` actor stream
   from a `@State Task` cancelled on disappear; download preview/multichannel WAVs through
   `createConfiguredURLRequest`.
4. **Process:** run `swift-format --configuration swift-format.json --in-place` on every modified
   Swift file. Run `cd Common && swift test` and the Xcode test schemes before committing. Bump
   version + create a git tag for the CLI change.

---

## Verification (end-to-end)

1. **Build/tests:** `cd Common && swift build`, `cd Common && swift test --filter Dialog`, then
   `swift build --target creature-cli`. Build the macOS app in Xcode (⌘B) and run app tests (⌘U).
2. **CLI smoke (against the dev server):**
   - `creature-cli dialog validate scene.json`.
   - `creature-cli dialog upsert scene.json` → then `dialog list` shows it.
   - `creature-cli dialog render --script-id <id> --persistence permanent` → prints `job_id`;
     confirm via `creature-cli websocket` and `animations list`.
   - `creature-cli dialog export-multichannel --script-id <id> --output /tmp/scene.wav` → open in
     Audacity, confirm 17 channels in the right per-creature lanes.
3. **GUI:** launch, open the new **Dialogs** sidebar section → Create New. Add turns, pick
   creatures, type tagged text; confirm debounced validation surfaces errors + missing-creature
   warnings and char limits. Save → appears in "List All" and survives a relaunch. Use **Listen**
   to play the mono preview; try **Regenerate** and the take picker. **Export** mono + 17-channel
   WAVs and open in Audacity. **Render** (permanent) → watch job progress → land on the rendered
   animation; play it. Edit + re-render; confirm provenance "Edit this script" round-trips.
