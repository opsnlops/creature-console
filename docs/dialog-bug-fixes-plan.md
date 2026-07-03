# Dialog Feature Bug Fixes — Implementation Plan

Three bugs found while testing the multi-character dialog feature (2026-07-02). Two are
client-side, one is server-side (creature-server).

## Bug 1 — Preview 404s after editing turns

**Symptom:** After adding/editing turns and clicking "Preview", the server returns
`generation '<uuid>' not found (expired or never existed)` until "Regenerate" is used.

**Root cause:** The server caches voice generations under
`cache_key = sha256(model | turns[voice,text])` (`DialogCache.cpp`). Editing, adding,
removing, or reordering a turn changes the cache key. The client keeps
`selectedGenerationId` in `DialogScriptEditor` `@State` and never clears it when turns
change, so the next preview asks for the old take under the *new* cache key →
`loadGeneration(newCacheKey, oldGenerationId)` fails → HTTP 404.

**Fix (client):** Clear the stale take whenever the turns change:

- `DialogScriptEditor`: `.onChange(of: script.turns)` → `selectedGenerationId = nil`.
  (Any turn mutation — text, creature, add/remove/reorder — changes the cache key, so
  clearing on any change is correct, and cheap: `nil` just means "latest / server decides".)
- `DialogPreviewPanel`: the cached-takes picker (`takes`) and `meta` badge are keyed by
  the same cache key, so they're stale too. Clear them via `.onChange(of: turns)` in the
  panel itself so it stays self-contained.

No server change: 404 for an explicit unknown generation id is correct API behavior.

## Bug 2 — Render status stuck on "Generating voices…"

**Symptom:** Rendering a dialog (observed with ad-hoc storage) leaves the progress card
on "Generating voices…" forever, even though the render succeeds.

**Root cause — a seed/completion race:** `DialogRenderPanel.render()` seeds
`JobStatusStore` with `JobProgress(status: .queued, progress: 0)` *after* the REST 202
returns. When the voice generation is already cached (which is exactly the state after
previewing), the render job finishes in well under a second, so the WebSocket
`job-complete` can arrive **before** the seed runs. `JobStatusStore.update(with: JobProgress)`
unconditionally overwrites `status`/`progress`, so the seed resurrects the terminal job
back to `queued`/`0.0`. Nothing will ever update it again → the panel shows the
`< 0.55` milestone label ("Generating voices…") forever. The same seeding pattern exists
in `DialogRerenderButton`, `AnimationTable`, and `SoundFileListView`.

**Fix (client, one place):** In `JobStatusStore.update(with: JobProgress)`, ignore
progress updates for a job that is already terminal (a terminal status is final;
completions arrive on the same ordered WebSocket pipeline, so the only out-of-order
producer is the client's own optimistic seed). This fixes every seeding call site at
once — no per-view changes. Add unit tests for the store: progress-after-completion must
not resurrect the job; normal progress→completion still works.

## Bug 3 — Multi-creature ad-hoc animations can't be replayed (server)

**Symptom:** A dialog with 2+ creatures saved as an ad-hoc animation plays at render
time (autoplay), but replaying it from the Ad-Hoc Animations list fails.

**Root cause:** `POST /api/v1/animation/ad-hoc/play` (`AnimationController.h`) hard-fails
with 422 ("Prepared animation targets multiple creatures; cannot auto-play.") when tracks
span more than one creature, because it derives the target universe from a single
creature. The dialog render's autoplay path already supports multi-creature playback by
validating that all creatures share one universe (`JobWorker.cpp` dialog autoplay
validation) — the play endpoint just never got the same treatment.

**Fix (server, DRY — do not duplicate the resolver):**

1. Extract a shared resolver, `creatures::resolveCommonUniverse(creatureIds)` →
   `Result<universe_t>`, in `src/server/creature/`. Error mapping:
   - creature not registered with a universe → `ServerError::Conflict` (→ HTTP 409,
     matching the endpoint's current behavior for unregistered creatures)
   - creatures on different universes → `ServerError::InvalidData` with a clear message
2. Use it in **both** places:
   - `JobWorker::handleDialogJob` autoplay validation (replaces the inline loop)
   - `AnimationController` `playPreparedAdHocAnimation` (replaces the single-creature
     guard: collect unique creature ids from tracks, resolve, play)
3. Generalize `SessionManager::interruptIdleOnly` to take the full set of creature ids:
   conflict if *any* target creature has an active non-idle session; cancel idle sessions
   for *all* target creatures (the existing `overlaps()` helper already does set-vs-session
   matching). Single caller updates with it.
4. Keep the endpoint's response message accurate for multi-creature animations.

Multi-universe ad-hoc animations remain rejected (framing data is per-universe), now with
a message that says *why* ("creatures span universes X and Y") instead of a blanket
"targets multiple creatures".

## Verification

- `cd Common && swift test` plus new `JobStatusStore` regression tests. App-target tests
  are co-located with their subject (`Sources/Creature Console/Model/Jobs/JobStatusStoreTests.swift`)
  and added to the "Creature Console Tests" target via explicit pbxproj references — that's
  the established pattern (see `AppStateTests.swift`); the `Creature Console Tests/` folder
  is a plain (non-synchronized) group, so files dropped there are not picked up.
- macOS xcodebuild test run.
- Server: build + existing test suite; manual replay of a saved 2-creature dialog.
- swift-format all touched Swift files; bump versions before committing.
