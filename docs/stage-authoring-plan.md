# Stage Authoring — Implementation Plan

> Client-side plan for Stage authoring and stage-aware head aiming in Creature Console.
> Tracking issue: opsnlops/creature-console#67. Server side: opsnlops/creature-server#119,
> shipped in server **3.37.0**.

## Context

During a rendered dialog scene the server now cycles idle animations on creatures that aren't
speaking, and — when the render is bound to a **Stage** — turns their heads toward whoever *is*
speaking, with per-creature reaction delays so the cast doesn't move in unison.

A Stage says where each creature physically sits and which way it faces. None of the server work is
observable until the Console can author one: **there is currently no way to create a Stage at all.**

The coordinates already exist in the Console — `SpatialStageLayout` in
`Sources/Creature Console/SpatialAudio/SpatialStageTypes.swift` — but they live in **UserDefaults**,
so the server can't see them, they don't survive a machine change, and they can't be shared. The goal
is **one document driving both spatial audio and head aiming**, not two copies that drift.

## Verified server contract

Read from `src/model/Stage.{h,cpp}`, `src/server/stage/helpers.cpp`, and
`src/server/ws/controller/StageController.h` at server 3.37.0 — not from prose.

### Routes

| Method | Path | Returns |
|---|---|---|
| GET | `/api/v1/stage` | `{count, items:[Stage…]}`, newest first by `updated_at` |
| GET | `/api/v1/stage/{id}` | one Stage |
| POST | `/api/v1/stage` | 201 + created Stage (server mints the UUID) |
| PUT | `/api/v1/stage/{id}` | 200 + updated Stage |
| DELETE | `/api/v1/stage/{id}` | 200 status envelope |
| GET | `/api/v1/stage/{id}/animations` | staleness report (below) |

Same shape as Storyboard, so `StoryboardMethods.swift` is the template.

### Document

```json
{
  "id": "uuid",
  "title": "Mainstage",
  "notes": "",
  "version": 1,
  "placements": [
    { "creature_id": "…", "x": -2.4, "y": 0.10, "z": -3.0, "yaw": 35.0,
      "audio_channel": 1, "gain": 1.0, "muted": false }
  ],
  "audio": {
    "monitoring_delay_ms": 10, "common_playout_delay_ms": 20,
    "background_music_gain": 0.7, "reverb_blend": 0.08
  },
  "created_at": 0,
  "updated_at": 0
}
```

`stageToJson()` emits exactly these eight keys. `placements` and `audio` are carried as opaque
`nlohmann::json` and re-emitted **verbatim** — per-placement extras (`gain`, `muted`,
`audio_channel`, `creature_name`, …) and the whole `audio` block are the Console's to define. That
opacity is what makes this one document instead of two.

### Validation (all 400 on failure)

From `src/server/stage/helpers.cpp`:

- `placements` — **required**, must be an array. Max **16** (`MAX_STAGE_PLACEMENTS`, one per creature
  audio lane; lane 17 is background music).
- `creature_id` — required non-empty string on every placement. **Duplicates rejected** — "a creature
  can only be in one place at a time."
- `x` / `y` / `z` — required, finite, within **±5 m** (`STAGE_COORD_LIMIT`). Out-of-range is treated
  as a unit mix-up (centimetres, or the Console's old absolute frame) and rejected loudly.
- `yaw` — required, must be present and numeric, finite. Any magnitude is accepted.
- `version` — optional int; must be `1` (`STAGE_CURRENT_VERSION`). A newer version is refused.
- `audio` — optional; must be an object when present. Never inspected.
- `id` / `created_at` / `updated_at` — server-managed, ignored on write.
- `title` ≤ 256 chars, `notes` ≤ 16384.

### Coordinate frame

```
origin (0,0,0) = the listener's head, facing −Z.  Metres, Y-up, right-handed
                 (the same axes AVAudioEngine already uses — only the origin moved).

  +x  listener's right          −x  listener's left
  +y  above the listener's ears −y  below   (bird heads sit slightly negative)
  −z  in front of the listener  +z  behind them
```

The ±5 m box *is* the stage — there is no `listener_*` field and no `stageWidth`/`stageDepth`.

`yaw` is an absolute heading in the stage frame, **not** relative to the listener: `0°` faces `+Z`,
`+90°` faces `+X`, `180°` faces away from the listener.

> **Normalization asymmetry — worth handling client-side.** `normalizeDegrees()` folds yaw into
> `(−180, 180]`, but the parser does *not* normalize on write; `stagePlacements()` normalizes on
> *read*. So the server stores whatever the Console sends and the gaze layer uses the folded value.
> If the Console sends `370°` it will display `370°` while the creature aims at `10°`. **Normalize in
> the Console before sending** so the stored document and the rendered behavior agree.

## Phases

### 2a. Stage model + CRUD in `Common/` ← the blocker

Nothing else in the issue is reachable without this.

- `Common/Sources/Common/Model/Stage/Types.swift` — `public typealias StageIdentifier = UUID`
  (real UUID, per the newer-code convention; the `String` identifier typealiases are legacy
  MongoDB-OID artifacts).
- `Stage.swift` — `Stage: Codable, Equatable, Hashable, Identifiable, Sendable` with snake_case
  `CodingKeys`, `Int64?` epoch-millisecond timestamps and `createdAtDate`/`updatedAtDate` helpers,
  mirroring `Storyboard`. Plus `UpsertStageRequest` carrying only the editable fields.
- `StagePlacement.swift` — `creature_id`, `x`, `y`, `z`, `yaw` (validated) alongside the
  Console-owned extras `audio_channel`, `gain`, `muted`, `creature_name`. Yaw normalized on
  construction. `StageAudioSettings` for the nested `audio` block.
- `StageLimits.swift` — mirror the server's caps so the Console fails locally with a good message
  instead of round-tripping a 400.
- `StageListDTO.swift`, `StageAnimationsDTO.swift`.
- `StageMethods.swift` — five CRUD calls + `listStageAnimations`, mirroring `StoryboardMethods`.
- `CacheInvalidation`: new case `stageList = "stage-list"`, and the matching string in
  `DebugMethods.swift`.
- Tests in `Common/Tests/CommonTests/StageTests.swift`: round-trip encoding, extras preservation,
  yaw normalization, cap enforcement, decoding a document with unknown keys.

**Decision — keep `audio` nested.** The server offered to flatten it. Nested costs the Console one
`Codable` level and avoids a server change; the block is entirely Console-owned either way.

### 2b. Point spatial audio at the server stage

`SpatialStageLayoutStore` moves from UserDefaults to the endpoints above, so the renderer and the
head aiming read the same document.

Two hazards the issue understates:

1. **The version numbers collide.** The local layout is at `version = 3`; the server's stage frame is
   `version = 1`. Same field name, different documents. `SpatialStageLayoutStore.load()` currently
   *rejects* anything with `version > currentVersion`, so conflating them silently discards stages.
   Keep the namespaces distinct.
2. **`migrateToCurrentVersion()` does not do what the issue claims.** At SpatialStageTypes.swift:90
   it only fixes a stale 80 ms monitoring delay — there is no re-origining in it. The listener
   subtraction (`x' = x − listenerX`, …) and folding `listenerYaw` into a rotation of the whole frame
   still have to be written.

Migrate any existing local layout once, on first run, then treat the server as the source of truth.

### 2c. Stage editor UI

Stages are a **first-class sidebar section** (`Stages → List All / Create New`), alongside Dialogs,
Storyboards and Playlists — not a surface reached through the Spatial Stage window. A stage is an
authored document; burying it inside the RTP monitor made it look like a setting of that feature.

Files live in `Sources/Creature Console/Stage/`, registered as a `PBXFileSystemSynchronizedRootGroup`
so new files there are picked up without hand-editing `project.pbxproj` (mirroring `SpatialAudio/`).

- **`StageMapView`** — the top-down ±5 m box with the listener at its centre, shared by both
  surfaces so they can't drift into drawing the same stage differently. Draggable when given an
  `onMove`, read-only without one.
- **`StageEditor`** — picker, map, per-creature inspector, spatial-mix settings, staleness, and
  explicit Save/Revert. Cross-platform: authoring on an iPad next to the perches is the natural way
  to capture real heights.
- **`StageTable`** — the list. Server-backed rather than SwiftData-mirrored; stages are few and only
  read while authoring, so a local cache plus an importer would be cost without benefit.

Per-creature **yaw** is the genuinely new input, with a plain-language readout ("Facing your left,
toward you") and a *Face Me* action. **Height leads the inspector** and shows on every map node:
elevation is what tells the audience *which* creature is being addressed, and a stage with everyone
at the same `y` throws that cue away.

The **Spatial Stage window keeps its job** — listening. It picks a stage, shows it with live audio
meters, and states plainly that geometry is edited under Stages. One editing surface, so the two
can't disagree about what's saved.

### 2d. Bind a stage to a render

- `POST /api/v1/animation/dialog` accepts an optional `stage_id`.
- `DialogScript` gains an optional `stage_id` — the script's usual stage.
- The request overrides the script's, which is how a travel rendition of a mainstage scene gets made
  (`JobWorker.cpp:1196`).
- Omit both → no head aiming, and rendered frames are byte-identical to a pre-#119 render.

Rendered animations are keyed by **(script, stage)** and stamped with `metadata.source_stage_id`, so
mainstage and travel renditions coexist rather than overwriting each other.

### 2e. Staleness

`GET /api/v1/stage/{id}/animations` returns `{count, stale_count, stage_updated_at, items[]}`, most
out-of-date first. An animation is `stale` when its `source_stage_updated_at` predates the stage's
current `updated_at` — move a creature and everything built on that stage is stale until re-rendered.
Surface it on the stage editor ("3 of 5 animations out of date").

## Out of scope

The per-creature `gaze` block — which input aims where, and its angular range — lives in the
controller's JSON configs in `creature-controller/config/`, which is the source of truth for creature
config. The Console may *show* whether a creature has one; it must not edit it.

## Gating for real testing

Code alone won't prove this works. Testing needs, in order:

1. Stage CRUD (2a) — nothing is reachable without it.
2. A `gaze` block with **measured** degrees in each creature config (separate work in
   `creature-controller`).
3. A stage with **real perch heights**.

Items 2 and 3 are measurement, not code. The server renders happily with no aiming at all, and that
is indistinguishable from a bug by eye.

Related: opsnlops/creature-server#120 — `mouth_slot` isn't linked to the `beak` input in any shipped
config, so lip sync may currently be driving body lean or head height. Unrelated to this work, but it
will be visible the moment anyone watches a bird closely during stage testing.
