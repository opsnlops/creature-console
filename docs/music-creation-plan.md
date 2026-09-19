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

### Keep-the-opening semantics

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
