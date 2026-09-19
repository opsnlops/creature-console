# Music Creation (console #197)

creature-server 3.47 (server #200) moved dialog background music to ElevenLabs
Music 2.5 and exposed every generation control: model, vocals, finetunes,
composition plans, audio references, conditioning, seeds, and a recipe endpoint
that hands a take's plan back. This plan re-thinks how the console makes music
around those controls.

## Goal

A take should be *iterated until it is right*, not re-rolled from a bare prompt.
Music gets its own place in the console — a **Music** section in the sidebar —
and the composer that lives there is the same view the dialog editor embeds, so
there is one music workflow, not two.

## What the server allows (and does not)

- Music is always composed **against an accepted dialog voice take**. Every
  music endpoint needs `script_id` + `dialog_cache_key` + `dialog_generation_id`,
  and the plan's total length must cover the dialog. There is no dialog-free
  music generation on the server, so the standalone Music section is a
  *workspace over dialogs*: pick a dialog with an accepted voice, then compose.
  Dialog-free music (a jingle, a bed for a playlist) would be a server feature;
  it is out of scope here and noted as a follow-up.
- Two request shapes, mutually exclusive: **prompt** (`prompt`,
  `duration_extension_ms`, `generation_mode`, `force_instrumental`) and
  **composition plan** (`composition_plan.chunks[1..30]`, optional `seed`).
  Common to both: `model_id` (`music_v2` | `music_v2_5`), `finetune_id` +
  `finetune_strength` (0–2), `store_for_inpainting` (default true).
- A chunk is either an **audio reference** (`song_id` + `range`, 3–120 s of a
  prior take, re-rendered — close, not sample-exact) or a **generation chunk**
  (`text`, `duration_ms` 3000–120000, `positive_styles`/`negative_styles` ≤50
  each, `context_adherence` low|medium|high, optional `conditioning_ref` +
  `condition_strength` low|medium|high|xhigh).
- The server rejects unknown fields and validates every limit with a full field
  path, so the console mirrors those limits in `DialogLimits` and only ever
  sends the keys the mode allows.
- New reads: `POST …/music/plan` drafts a plan sized to the take;
  `GET …/music/generated/{id}/recipe` returns a take's recipe (404 once the
  candidate aged out); `GET …/music/finetunes` lists finetunes (45 public
  ones on prod today).
- Every job result now carries the recipe (`model_id`, `song_id`,
  `request_kind`, `composition_plan`, `song_metadata`, and whichever of
  `generation_mode` / `force_instrumental` / `seed` / `finetune_*` applied).
  `song_id` + `composition_plan` are what the next request feeds on.
- Promotion (3.47.3) requires the candidate's source voice to equal the
  script's accepted voice — the console's existing `matches()` rule — so
  "promote A, listen, promote B" works.

Prod is already on 3.47 (verified 2026-09-18: the finetunes endpoint answers).

## Console design

### Common package

`Common/Sources/Common/Model/DTO/DialogMusicDTO.swift` grows the full contract:

- `DialogMusicModel` (`music_v2`, `music_v2_5`), `MusicContextAdherence`,
  `MusicConditionStrength`. The console and CLI always compose with Music
  2.5 (April: "there's no point in keeping 2.0"); the type exists so a
  recipe can still name what an older take was made with.
- `MusicAudioRange { songId, startMs, endMs }` ↔ `{song_id, range:{start_ms,end_ms}}`.
- `MusicPlanChunk`: `.audioReference(MusicAudioRange)` |
  `.generation(MusicGenerationChunk)`; decoded by the presence of `song_id`.
  `MusicGenerationChunk` tolerates ElevenLabs' explicit `null`
  `conditioning_ref` / `condition_strength` and never encodes them when nil.
- `MusicCompositionPlan { chunks }` with `totalDurationMilliseconds`, a
  `validate(dialogDurationMs:)` that reproduces the server's limits with the
  same field paths, and the two plan transforms the UI needs:
  `keepingOpening(upTo:songId:)` (audio-ref the kept span, keep the remaining
  generation chunks, split a straddling chunk) and
  `conditioned(on:strength:)` (put a conditioning ref on every generation
  chunk).
- `DialogMusicRequest` becomes prompt-or-plan (`composition` enum) plus the
  common knobs. The existing prompt initializer keeps working for the CLI and
  older call sites; encoding emits only the keys the chosen mode allows.
- `DialogMusicRecipe` decodes the recipe keys; `DialogMusicGenerationResult`
  gains an optional `recipe` decoded from the same object (nil against a
  pre-3.47 server, so nothing breaks).
- `DialogMusicPlanRequest` / `DialogMusicPlanResult`, `MusicFinetune` /
  `MusicFinetuneList`.
- `DialogLimits` gains the plan limits.
- `DialogMethods`: `draftDialogMusicPlan`, `getDialogMusicRecipe`,
  `listMusicFinetunes`.

### CLI

`creature-cli dialog music generate` gains `--allow-vocals`,
`--finetune`, `--finetune-strength`, `--plan <file.json>` and `--seed` (plan
mode). New subcommands: `plan` (draft a plan to stdout or `--output`),
`recipe <generation-id>`, `finetunes`. The stub server in the tests grows the
three new client methods.

### App

New folder `Sources/Creature Console/View/Music/`:

- **`MusicCreationView`** — the composer, the one view used in both places.
  Input is a `MusicSubject` (script id + title, accepted voice, voice
  freshness, accepted music, unsaved-changes flag) and the two callbacks the
  editor already uses. Sections:
  1. Accepted music card (as today) plus **Open recipe** — fetches the recipe
     and loads it into the composer so accepted music can be iterated.
  2. Composer with a **Describe / Plan** switch. *Describe* is the prompt box
     with style (track / loop / ambience), music-after-dialog tail, and
     **Draft plan** which turns the prompt into an editable plan. *Plan* is the
     chunk editor. Both share the finetune picker and, in plan mode, the seed.
  3. Candidates. Each card shows the recipe the server actually used, and
     offers **Play with dialog**, **Accept**, **Edit plan** (load into the
     plan editor), **Keep the opening…** (audio-ref the first N seconds of
     this take and regenerate the rest) and **Sound like this take**
     (conditioning ref on every generation chunk).
- **`MusicPlanEditor`** — chunk list: text, duration, positive/negative style
  chips, adherence, conditioning indicator, running total against the dialog
  length, add/remove/reorder, and the validation message the server would
  give.
- **`MusicFinetunePicker`** backed by a small `MusicFinetuneStore`
  (`@Observable`, fetched once per launch, refreshable).
- **`MusicWorkspaceView`** — the sidebar destination. A list of dialogs from
  SwiftData (`DialogScriptModel`) with voice / music status; selecting one
  fetches the canonical script, learns the current cache key from the free
  takes lookup (so voice freshness is real, not assumed), and shows
  `MusicCreationView` for it. Dialogs without an accepted voice are listed
  but explain what to do.

`DialogMusicPanel` and `DialogMusicCandidate` leave `DialogPreviewPanel.swift`;
`DialogScriptEditor` embeds `MusicCreationView` instead. Sidebar gains a
**Music** section ("Compose") between Dialogs and Storyboards.

Audition and playback code moves with the panel unchanged. Candidates stay
session state; promotion remains the explicit commit point.

### Keep-the-opening semantics (phase 1; superseded by the piece model in phase 2)

Given the take's plan and a keep point `k` ms: chunks whose span ends at or
before `k` are folded into one audio-reference chunk `[0, k)`; a chunk that
straddles `k` contributes its head to the reference and its tail as a
generation chunk with the same text and styles; later chunks are copied. The
reference must be ≥ 3 s and any tail ≥ 3 s, otherwise the UI clamps `k` to the
nearest legal value and says so. The reference span is re-rendered, so the card
says "close to the original", never "identical".

## Versions

Console 2.55.0 → 2.56.0 (feature), CLI tools 2.77.5 → 2.78.0 in lockstep,
`debian/changelog` entry, tag `v2.56.0`.

## Verification

- `cd Common && swift test` (new DTO, plan-transform, and CLI tests).
- macOS build with a private derived-data path.
- Linux container build of the four packaged products.
- Live against prod: draft a plan for a dialog with an accepted voice,
  generate, keep-the-opening from that take, check the recipe endpoint, promote.

## Follow-ups (not in this change)

- Dialog-free music generation (server feature).
- Persisting candidates across launches (needs a server list endpoint).

---

# Phase 2–4: refine, don't re-roll; a library; pick an existing piece (console #199, server #202)

April, 2026-09-18, on seeing the native ElevenLabs editor: "What the native one
does is allow you to refine the music. It doesn't just re-generate it." And:
"It would be nice if I could play around with a piece of music in the big
editor, and then when I'm creating a dialog be able to select one that's
already been created (in addition to making a new one)."

## The finding that makes it possible

An audio-reference chunk comes back **identical** to its source, up to MP3
re-encoding. Measured on prod (candidate `8ae6ad84…` built from `22ae492b…`):
the referenced 0–6.76 s had sample correlation 0.999 at 0 ms lag; the freshly
composed tail, conditioned on the source with the same seed, 0.72. The "close,
not sample-exact" caveat above is wrong for this path (server #200 told). So:

- **Refine in place is real.** Edit one section; only that section is
  composed; every other section is referenced and comes back the same.
- **A library piece can be fitted to a dialog with no new server endpoint**:
  a dialog-bound generation whose plan references the piece is a faithful
  copy, promoted through the existing path, keeping the #136 provenance rule.

## The model (Common, done)

`MusicPiece` = `songId` + `durationMilliseconds` + `[MusicSection]`. A section
holds its editable `content` (a generation chunk), the `committedContent` its
audio was made from, and the `span` of that audio in the current song. A
section is dirty when content ≠ committed (length counts) or it has no audio.

- `refinementPlan(conditionStrength:)`: clean sections → audio references to
  their span; dirty sections → generation chunks conditioned on the current
  song (whole song, capped at one chunk's maximum), unless the section carries
  its own conditioning. A piece with no audio composes everything.
- `committed(songId:durationMilliseconds:)` after a successful refinement:
  every section's audio now lives at its offset in the new song.
- `reverted()`, `insertSection`, `removeSection`, `moveSection`,
  `splitSection` (a clean section splits into two clean sections — the
  reference is just trimmed), global styles (the styles every section shares;
  add/remove propagates), names via the `[Name]` prefix.
- `MusicPiece(songId:durationMilliseconds:plan:)` turns a generated take into
  a piece. A plan chunk that was itself an audio reference has no content on
  the server; it becomes "Kept from an earlier take" until renamed or
  rewritten — which is why saved pieces carry their sections (phase 3).

## Phase 2 — the big editor refines (console, this branch)

`MusicCreationView` becomes an editor over a *current piece* rather than a
generator of candidates:

- **Starting a piece**: Describe (prompt → generate, or draft a plan) or start
  from an empty plan. The first take becomes the current piece.
- **Timeline**: sections as proportional blocks over the piece's waveform
  (decoded locally from the candidate MP3 with AVAudioFile, peak bins), a
  playhead, click-to-seek, play-from-section, the dialog's length as a marker
  when the piece is dialog-bound. Dirty sections are marked. Global style
  chips above; a section inspector below (name, directions, length, lean
  into / avoid, adherence, sounds-like).
- **Apply** builds `refinementPlan()`, validates, generates (plan mode, same
  seed by default), and on completion commits the piece and adds the take to
  **Versions** (what candidates were): play, make current, accept for render.
  **Revert** discards edits. Nothing regenerates until Apply.
- Playback with a position needs a small `MusicPiecePlayer`
  (AVAudioPlayer + observed time) that borrows `AudioManager`'s session
  handling; nothing in the app today exposes seek or position.
- The dialog editor embeds the same view; the sidebar Music page shows it
  per dialog until phase 4 gives it a library.

## Phase 3 — the library (creature-server)

Design in `creature-server/docs/music-library-plan.md`. In one line: dialog-free
generation (`POST /api/v1/music/generate`, length from the request), saved
pieces with versions (`POST …/music/generated/{id}/save`, `GET/PUT/DELETE
/api/v1/music[/{id}]`), permanent WAVs under `music/`, a `music-piece-list`
cache invalidation, and each version carrying the console's `sections` so a
piece reopens editable.

## Phase 4 — library in the console; pick an existing piece

- Sidebar **Music**: *Library* (SwiftData mirror `MusicPieceModel`, importer,
  `music-piece-list` invalidation, list with play/duration/versions) and *New
  Piece* (the editor with an explicit length, no dialog). Opening a piece
  loads its current version's sections and song into the editor; Apply saves
  a new version; versions are the server's list.
- Dialog editor's music step gains **Use an existing piece**: pick from the
  library; if the piece covers the dialog, the plan is one audio reference of
  its current song (music may run past the dialog); if shorter, a conditioned
  generation chunk extends it. Generate, listen, accept — the existing path.
  **Save to library** on any dialog take or accepted music (same save
  endpoint; the cache is shared).
- Risk: song ids live at ElevenLabs. If one is gone, references fail; the
  fallback is composing the piece again from its saved sections (no
  conditioning). The UI must say which happened.
