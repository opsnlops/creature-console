# Back-fill CLI Utility — Implementation Plan

## Goal

The complement to `migrate-database`: copy the content you create on the **travel** server
while on the road back into the **mainline** server. Scoped to the collections that actually
get authored on the road — **animations**, **dialog scripts**, and **storyboards** — rather
than the whole database.

## Identity

Entities are matched on their UUID `id` field, **not** the Mongo `_id` (the system doesn't use
the OID). Documents are upserted by `id`, so inserts preserve the source `_id` and the two
servers stay `_id`-consistent for future `migrate-database` runs.

## CLI Surface

```
creature-cli util backfill \
    --mainline-server mainstage.example.com \
    --travel-server   travel.example.com \
    [--update-existing] [--dry-run] [--yes] [--skip-cache-invalidation]
```

- Source = `--travel-server`, destination = `--mainline-server` (with `--*-port` options).
- **Add-only by default**: only items whose `id` is missing on the mainline server are copied;
  existing mainline documents are untouched. `--update-existing` also overwrites matches.
- `--dry-run` previews; `--yes` skips prompts (items with missing references are skipped).

## Reference Resolution

Dialog scripts reference the **creature** speaking each turn. Storyboards reference
**animations, creatures, fixtures, playlists, and dialog scripts** (via opaque tile actions),
plus **sounds** by file name (files on disk — can't be verified in the DB).

Reference extraction lives in `ContentReferences` (pure, unit-tested). Before copying a
reference-bearing item, the back-fill checks each reference against the mainline server —
counting items being copied in the same run as present (animations and dialog scripts are
written before storyboards). For any missing reference the user is prompted:

- **[c]** copy the item anyway (leave the reference dangling)
- **[d]** pull the missing referenced entity from travel across too, then copy the item
- **[s]** skip this item
- **[a]** abort

Sounds are surfaced as "can't verify" notes, never blocking.

## Cache Invalidation

After writing, the mainline **creature-server** is told to invalidate the caches for exactly
the collections that changed, so connected consoles re-pull. This uses the existing
`CreatureServerClient` methods (`invalidateAnimationCache()`, `invalidateDialogScriptCache()`,
`invalidateStoryboardCache()`, plus creature/fixture/playlist for any copied dependencies) —
**not** direct API calls. The call targets the server named by the global `--host`/`--port`
options (the creature-server HTTP API, separate from the Mongo host). A failed invalidation is
a warning, not fatal — the data is already written. `--skip-cache-invalidation` disables it.

### Server-side dependency

The creature-server only had `cache-invalidate` HTTP routes for creature/animation/playlist.
The missing routes (`storyboard-list`, `dialog-script-list`, `fixture`, `sound-list`,
`ad-hoc-animation-list`, `ad-hoc-sound-list`) were added to `DebugController.h` so the client's
existing methods have endpoints to hit.

## Code Layout

- `Common/Sources/CreatureCLI/backfillCommand.swift` — `CreatureCLI.Util.Backfill` + the
  `BackfillPlan` engine (planning, reference analysis, apply-with-prompts, cache invalidation).
- `Common/Sources/CreatureCLI/ContentReferences.swift` — `EntityReference` + `ContentReferences`
  extractor (storyboard tile actions, dialog-script turns), pure and testable.
- `Common/Sources/CreatureCLI/MongoConnectionSupport.swift` — shared `connectCreatureDatabase`
  helper, reused by `migrate-database` and `backfill`.
- `Common/Tests/CommonTests/ContentReferencesTests.swift` — extractor tests.
