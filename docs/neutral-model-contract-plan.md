# Adopting the neutral Creature Server model contract

Tracking issue: [console#87](https://github.com/opsnlops/creature-console/issues/87)
(consolidates console #83, #84, #85). Server side: creature-server PR #170,
"Separate model layer from oat++", shipping as server **3.45.0**.

## What changed on the server

The server's model layer no longer goes through oat++ DTOs. Every model now has a
hand-written `…ToJson` / `…FromJson` pair built on `src/model/JsonCodec.h`, and that
codec is deliberately strict:

- **Unknown fields are rejected** at most model boundaries (`json_codec::rejectUnknownFields`).
  `Animation`, `AnimationMetadata`, `Track`, `Playlist`, `PlaylistItem`, `Input`,
  `StreamFrame`, `Notice`, `VirtualStatusLights`, and `Creature`'s nested `inputs` / `gaze`
  all reject keys they don't know. Top-level `Creature` does **not** reject unknown fields
  yet — it rejects malformed known fields and the reserved `_id` — but per April's
  clarification on #87 that tolerance is not part of the contract and the Console must not
  lean on it. That's why `realData` comes off the wire rather than being left to ride along.
- **Absent means absent.** Optional values are omitted from responses, never written as
  `null`, and requests are expected to do the same. An empty string is *not* an accepted
  stand-in for absent — `json_codec::optionalString` rejects an empty value unless the
  caller explicitly allows it.
- **Identifiers must be UUID-shaped** (`isUuidShape`) — `animation_id`, `creature_id`,
  `fixture_id`, `source_script_id`, `source_stage_id`, playlist ids, and the entries of
  `speech_loop_animation_ids` / `idle_animation_ids`.
- **Values are range-checked**: `playlist_item.weight` ∈ 1…999, `audio_channel` ∈ 1…16,
  `channel_offset` ≤ 511, `input.width` > 0, `milliseconds_per_frame` > 0, input slot
  ranges must not overlap or run past DMX channel 512, animation ids must be unique
  within a list, and a `Track` must carry **exactly one** of `creature_id` / `fixture_id`.

## What this breaks in the Console today

These are not stylistic cleanups. Each one is a concrete failure against 3.45.0, in
rough order of severity.

### 1. Animation metadata fails to decode when `note` is empty

`animationMetadataToJson` omits `note` when it's empty. `AnimationMetadata.note` is a
non-optional `String` decoded with the synthesized `Codable`, so the whole animation
fails to decode. This is console#83.

### 2. Fixture-only tracks fail to decode

`trackToJson` omits `creature_id` for a fixture track. `Track.creatureId` is a
non-optional `CreatureIdentifier`, so any animation containing a fixture track throws
on decode.

### 3. Saving an animation is rejected

`AnimationMetadata` encodes `last_updated`, a field the server has **never** had — grep
`last_updated` across the server tree and there are no hits. Today's oat++ DTO ignores
it; `animationMetadataFromJson` rejects it as an unknown field. That kills
`POST /api/v1/animation` outright, which means the animation editor's Save and both
rename paths (`AnimationTable.performAnimationRename`, `creature-cli animations rename`).

### 4. Round-tripping an animation destroys provenance — this is broken *today*

`AnimationMetadata` has no representation for `render_seed`, `source_stage_placements`,
or `source_render_choices`. Renaming an animation is a fetch → mutate → re-POST round
trip, so renaming a stage-rendered or dialog-rendered animation silently strips the
stage placements, render seed, and per-creature render choices from the stored document.
That is live data loss against the current server, not just 3.45.0.

`Track` has the mirror problem in the other direction: it always encodes `creature_id`,
so a fixture track re-posted from the Console would send `creature_id: ""`, which
violates the exactly-one-owner rule and is rejected.

### 5. Playlist weights aren't bounded

`PlaylistItem.weight` is an unbounded `UInt32`. The add sheet's placeholder says
"1-999" but only rejects 0, and the inline weight editor doesn't validate at all, so a
weight of 1000+ is accepted locally and rejected by the server on save. Total-weight
math (`items.reduce(0) { $0 + $1.weight }`) accumulates in `UInt32` and traps on
overflow — with the new 999 ceiling and 256-item ceiling that's unreachable, but the
accumulator should be widened anyway since it currently runs on unvalidated input.

### 6. Creature configuration is incomplete and carries an invented field

`Creature` has no `mouth_input` and no `gaze`, so the CLI's export/validate round trip
is the only way to see or edit them, and any future Console-side creature POST would
drop them. It also encodes `realData`, which does not exist anywhere on the server —
it's a Console invention that no code outside `Creature` itself reads.

## Plan

Branch: `agent/87-neutral-model-contract`. One branch, staged commits, in this order —
each stage is independently testable and stage 1 is the one that unblocks 3.45.0.

### Stage 1 — Animation, metadata, and tracks

`Common/Sources/Common/Model/Animation/`

- **`AnimationMetadata`**
  - Hand-write `init(from:)` / `encode(to:)`; the synthesized conformance is what puts
    `last_updated` on the wire and what makes `note` mandatory.
  - Required on decode: `animation_id`, `title`, `milliseconds_per_frame`, `sound_file`,
    `number_of_frames`, `multitrack_audio`. Everything else `decodeIfPresent`.
  - Remove `last_updated` from `CodingKeys`. Keep `lastUpdated` off the DTO entirely —
    `AnimationMetadataModel` (SwiftData) can keep a local "when did we cache this"
    column if it wants one, but it is not a server field. The CLI's `animations list`
    "created" column comes off with it.
  - Add the missing provenance: `renderSeed: UInt64?`, `sourceStagePlacements`,
    `sourceRenderChoices: [CreatureRenderChoice]?` (new type mirroring
    `{creature_id, speech_loop_animation_id, idle_animation_id?, idle_start_offset?}`).
    `sourceStagePlacements` mirrors the server's free-form-but-validated array; model it
    with the existing `StagePlacement` type if it fits, otherwise `[JSONValue]` so an
    unknown extension key survives a round trip instead of being dropped.
  - Encode: omit every optional that is absent, omit `note` when empty, and keep
    `source_stage_id` / `source_stage_updated_at` paired (the server rejects one without
    the other).
- **`Track`**
  - Model the owner as exactly one of creature/fixture rather than a required
    `creatureId` plus an optional `fixtureId`. An enum (`TrackOwner.creature(id)` /
    `.fixture(id)`) is the honest shape; a computed `creatureId` keeps most call sites
    compiling.
  - Decode: accept exactly one, throw a clear `DecodingError` on zero or both.
  - Encode: emit only the owner that is set; never emit an empty string.
- **`Animation`** — no wire change, but `metadata.animation_id` must equal `id` and the
  track `animation_id`s must match, which the initializer already enforces for metadata.

### Stage 2 — Creature configuration

`Common/Sources/Common/Model/Creature/`

- Add `mouthInput: String?` (`mouth_input`).
- Add `GazeConfig` / `GazeAxis`:
  `gaze: { pan?, elevation?, cock? }`, each axis
  `{ input, degrees_at_min, degrees_at_max, listening_amount? }`. Omit an axis when
  absent; omit `gaze` entirely when no axis is set.
- Drop `realData` from the DTO and from `CreatureModel`. It exists nowhere on the server,
  nothing outside `Creature` itself reads it, and the server's current tolerance for
  unknown top-level creature fields is explicitly not something to depend on.
- Decode stays tolerant of legacy `null` (Swift's `decodeIfPresent` already maps `null`
  to `nil`, so this is mostly free once the fields are optional) but encode never emits
  it.
- Keep `runtime` decode-only — it's a server-side view, never part of a config POST.
- Surface `mouth_input` and gaze in `CreatureDetail` / `CreatureConfiguration` so the
  new fields are visible rather than merely modelled.
- Add the write path so the omit-nulls contract has a real caller:
  `upsertCreature(_:)` → `POST /api/v1/creature`, and
  `registerCreature(_:universe:)` → `POST /api/v1/creature/register` (which wants an
  envelope, `{"creature_config": "<the config JSON, as a string>", "universe": <int>}`).
  Expose the first as `creature-cli creatures import <file.json>`.

### Stage 3 — Playlists

- `PlaylistItem`: validate `weight` ∈ 1…999 and `animation_id` as a UUID at the wire
  boundary. Add a shared `PlaylistLimits` (mirroring `StageLimits` / `DialogLimits`) so
  the UI and the model agree on one constant.
- `PlaylistEditSheets`: enforce the range in **both** the add sheet and the inline weight
  editor. Per the issue, invalid input must stay on screen with visible validation
  rather than silently dismissing the editor.
- Widen the total-weight accumulator to `UInt64` in `PlaylistDetailComponents` and
  anywhere else weights are summed.

### Stage 4 — Sweep the remaining server-backed models

`DialogScript`, `DmxFixture`, `Sound`, `AdHocExchange`, `StreamFrameData`,
`VirtualStatusLightsDTO`, `Notice`, `CacheInvalidation`, `ServerLogItem`,
`PlaylistStatus`. The audit is: does anything require a key the server now omits, and
does anything encode a placeholder on the way back out?

**Result: clean, with one exception.** These models already use `decodeIfPresent … ?? ""`
for everything the server omits and `encodeIfPresent` for everything optional.
`DmxFixture` omits `assigned_universe` correctly, `Sound` defaults every embedded-metadata
field, `CacheInvalidation` already collapses unknown cache types to `.unknown`, and
`PlaylistStatus` already spells `current_animation` in snake case. Rather than churn code
that's already right, the audit is preserved as an executable assertion — see
`WritableModelNullSweepTests`, which fails if a future optional is added with a plain
`encode`.

The exception was `DialogScriptTurn`. Its `id` is a client-only UUID, minted fresh on every
decode and deliberately excluded from `CodingKeys` — but it was still counted by the
synthesized `Equatable`, so a turn was never equal to itself across a round trip. That made
every equality check involving a `source_script_turns` snapshot silently useless, including
the "round trip preserves meaning" test #87 asks for. Equality and hashing now match the
wire: creature and text.

That was masking a live bug. `DialogScriptEditor.isDirty` is `script != original`, and the
save path sets `original = saved` from the server's response — whose turns carry fresh ids.
So after any save the editor was permanently dirty regardless of content, and `isDirty`
gates `renderScriptId`, the Render button, take acceptance, and music promotion. The file
already carried a local workaround (`turnContent` mapping turns to `creatureId\0text`
strings) with a comment describing the symptom, which is now unnecessary and gone.

### Stage 5 — Fixtures and tests

Swift Testing suites in `Common/Tests/CommonTests/`, using JSON fixtures that are
byte-for-byte what the server emits:

- Creature: Beaky-shaped (inputs + gaze + mouth_input + both animation-id lists) and
  minimal (every optional absent). Assert the encoded JSON contains **no** `null` and
  none of the absent keys.
- Animation: creature-only tracks, fixture-only tracks, mixed, no provenance, dialog
  provenance, stage provenance. Assert a decode → encode round trip preserves meaning
  and invents nothing.
- Playlist: weight boundary fixtures at 1 and 999, rejection coverage for 0 and 1000,
  non-UUID `animation_id` rejection.
- A shared assertion helper — "this encoded payload contains no JSON null anywhere" — is
  worth writing once and reusing across all three.

## Decisions

Settled with April before starting:

- All five stages land on one branch, `agent/87-neutral-model-contract`.
- The Creature work includes the client write path and a CLI `creatures import`, not
  just the model — see stage 2.
- `lastUpdated` is removed outright, from the DTO *and* from `AnimationMetadataModel`.
  It was never a server field; keeping a local-only variant would just be a differently
  shaped invention.
- The `String` → `UUID` identifier migration is deferred to its own issue.

## Deliberately out of scope

**Migrating the `String` identifier typealiases to `UUID`.** `AnimationIdentifier`,
`CreatureIdentifier`, `PlaylistIdentifier`, `SoundIdentifier`, and
`DmxFixtureIdentifier` are still `String`. Issue #87 asks for RFC 4122 UUIDs for every
entity identifier, and that is the right long-term shape (see the existing
`DialogScriptIdentifier` / `StageIdentifier` / `TrackIdentifier`, which are real
`UUID`s). But changing those five typealiases touches essentially every file in the app
and would bury the contract work it's meant to support.

The contract requirement — "the server must receive UUID-shaped strings" — is met by
validating at the wire boundary in stage 1–3. The typealias migration should be its own
issue, done per-identifier, after this lands.

## Verification

- `cd Common && swift test` — 561 passing
- macOS and iOS Xcode test targets (`xcodebuild test`, with its own `-derivedDataPath`).
- Linux container build of all three CLI products before tagging, per CLAUDE.md.
- Live check against a 3.45.0 server: `creature-cli animations rename` on a
  stage-rendered animation, then `creature-cli animations detail --json` to confirm
  `render_seed`, `source_stage_placements`, and `source_render_choices` survived.
