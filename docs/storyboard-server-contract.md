# Storyboard — Server Contract

This is the **single source of truth** for the server-side storage of Storyboards, written so the
server CRUD can be implemented in parallel with the Creature Console client. Storyboards are a
**client-driven** feature: the server only persists the JSON document and broadcasts a cache
invalidation. It does **not** interpret tile actions.

Mirror the existing **DialogScript** implementation exactly — it's the template:
- `src/model/DialogScript.h` (+ `.cpp`)
- `src/server/ws/dto/DialogScriptRequestDto.h`
- `src/server/ws/controller/DialogScriptController.h`
- the `dialog-script-list` cache-invalidation wiring

> **Most important rule:** store each tile's `action` (and ideally the whole `tiles` array) as
> **opaque JSON**, preserved verbatim. Do **not** validate or enum-restrict the action `type`. The
> client evolves action types independently; the server must round-trip unknown shapes losslessly so
> old/new clients interoperate.

---

## Endpoints — base `/api/v1/storyboard`

| Method | Path | Body | Success | Errors |
|---|---|---|---|---|
| GET | `/api/v1/storyboard` | — | `200` `{count, items}` (items newest-first by `updated_at`) | 500 |
| GET | `/api/v1/storyboard/{id}` | — | `200` `Storyboard` | 404 (no such id), 400 (id not UUID-shaped) |
| POST | `/api/v1/storyboard` | `UpsertStoryboardRequest` | `201` full `Storyboard` (server-stamped id + timestamps) | 400 (shape error) |
| PUT | `/api/v1/storyboard/{id}` | `UpsertStoryboardRequest` | `200` updated `Storyboard` (preserves `created_at`, bumps `updated_at`) | 400, 404 (never creates-by-id) |
| DELETE | `/api/v1/storyboard/{id}` | — | `200` `{status, code, message}` (StatusDto) | 404 |

All JSON over HTTP. Same `StatusDto` shape used elsewhere.

---

## Data shapes

### `Storyboard` (response)
```json
{
  "id": "b4f1c0de-1111-2222-3333-444455556666",
  "title": "Halloween Front Porch",
  "notes": "Beaky greets trick-or-treaters; Mango heckles.",
  "tiles": [ /* StoryboardTile[] */ ],
  "created_at": 1748579999000,
  "updated_at": 1748580015000
}
```
- `id` — server-managed UUID (lowercase string). Stamped on POST; the URL is authoritative on PUT.
- `title` — required, non-empty. **Max 256 chars.**
- `notes` — optional. **Max 16384 chars.**
- `tiles` — array. **Max 200 tiles.** Stored verbatim (see opaque-JSON rule).
- `created_at` / `updated_at` — server-managed **int64 epoch milliseconds** (NOT ISO-8601). Stamped on
  create; `created_at` preserved and `updated_at` bumped on update.

### `StoryboardTile`
```json
{
  "id": "9a7c6b54-aaaa-bbbb-cccc-ddddeeeeffff",
  "x": 0.08, "y": 0.10, "width": 0.22, "height": 0.18,
  "label": "Greet",
  "sf_symbol": "hand.wave",
  "tint_color_hex": "#34C759",
  "action": { "type": "ad_hoc_speech", "creature_id": "e93b9a7a-1704-11ef-84b9-3b37dddeb225", "resume_playlist": true }
}
```
- `id` — client-generated UUID (lowercase string), **part of the document** (sent and stored).
- `x`,`y`,`width`,`height` — doubles in `[0,1]` (fractions of the card). Server may store as-is; the
  client clamps. (Optional: clamp server-side too — harmless.)
- `label` — string. **Max 256 chars.**
- `sf_symbol` — SF Symbol name (string).
- `tint_color_hex` — `#RRGGBB` string.
- `action` — **opaque tagged object**: always has a string `type`; other keys vary by type. **Store
  verbatim.**

### `UpsertStoryboardRequest` (POST/PUT body)
Only the editable fields:
```json
{ "title": "Halloween Front Porch", "notes": "…", "tiles": [ /* StoryboardTile[] */ ] }
```
Any `id` / `created_at` / `updated_at` in the body must be **ignored** (server-managed). Prefer the
lenient approach DialogScript adopted in 3.15.1 (accept and ignore extra fields rather than 400 on
"unknown field").

### List response
```json
{ "count": 3, "items": [ /* Storyboard[], newest-first by updated_at */ ] }
```

---

## Action `type` reference (client-defined; store verbatim, do not validate)

These are the v1 action shapes the client emits. The server should treat `action` as opaque — this
table is informational so you can sanity-check round-tripping. Identifiers are lowercase strings;
`universe` is an optional int (omitted when "follow active universe").

| `type` | params |
|---|---|
| `play_animation` | `animation_id`, `universe?`, `interrupt` (bool), `resume_playlist` (bool) |
| `ad_hoc_speech` | `creature_id`, `resume_playlist` (bool) |
| `live_control` | `creature_id`, `universe?` |
| `start_playlist` | `playlist_id`, `universe?` |
| `stop_playlist` | `universe?` |
| `play_sound` | `file_name` |
| `render_dialog` | `script_id` |
| `fixture_on` | `fixture_id` |
| `fixture_off` | `fixture_id` |
| `fixture_pattern` | `fixture_id`, `pattern_id`, `stop_after_ms?` |
| `fixture_details` | `fixture_id` |
| *(future types)* | the server must preserve any unknown `type` + its keys verbatim |

---

## Full example (POST body → 201 response adds id/timestamps)

```json
{
  "title": "Halloween Front Porch",
  "notes": "Beaky greets; Mango heckles; porch lights.",
  "tiles": [
    { "id": "11111111-1111-1111-1111-111111111111", "x": 0.06, "y": 0.08, "width": 0.26, "height": 0.20,
      "label": "Greet", "sf_symbol": "hand.wave.fill", "tint_color_hex": "#34C759",
      "action": { "type": "ad_hoc_speech", "creature_id": "e93b9a7a-1704-11ef-84b9-3b37dddeb225", "resume_playlist": true } },
    { "id": "22222222-2222-2222-2222-222222222222", "x": 0.40, "y": 0.08, "width": 0.26, "height": 0.20,
      "label": "Spooky Laugh", "sf_symbol": "theatermasks.fill", "tint_color_hex": "#FF9F0A",
      "action": { "type": "play_animation", "animation_id": "400b47b2-4ab0-462f-8101-c81b5f187452", "universe": 2, "interrupt": true, "resume_playlist": true } },
    { "id": "33333333-3333-3333-3333-333333333333", "x": 0.06, "y": 0.40, "width": 0.26, "height": 0.20,
      "label": "Live: Mango", "sf_symbol": "gamecontroller.fill", "tint_color_hex": "#0A84FF",
      "action": { "type": "live_control", "creature_id": "4754fc0e-1706-11ef-931d-bbb95a696e2e", "universe": 2 } },
    { "id": "44444444-4444-4444-4444-444444444444", "x": 0.40, "y": 0.40, "width": 0.26, "height": 0.20,
      "label": "Porch On", "sf_symbol": "lightbulb.fill", "tint_color_hex": "#FFD60A",
      "action": { "type": "fixture_on", "fixture_id": "porch-floods" } },
    { "id": "55555555-5555-5555-5555-555555555555", "x": 0.72, "y": 0.40, "width": 0.22, "height": 0.20,
      "label": "Scene", "sf_symbol": "slider.horizontal.3", "tint_color_hex": "#BF5AF2",
      "action": { "type": "fixture_details", "fixture_id": "porch-floods" } }
  ]
}
```

---

## Cache invalidation

After a successful POST / PUT / DELETE, broadcast the existing WebSocket cache-invalidate message
with a new cache type:
```json
{ "command": "cache-invalidate", "payload": { "cache_type": "storyboard-list" } }
```
Add `storyboard-list` to the server's `CacheType` enum/handling (and the 50 ms settle delay used by
the other invalidations). The client refetches the full list on receipt.

---

## Storage

- New Mongo collection (e.g. `storyboards`), same pattern as dialog scripts. The server stamps its own
  `id` (UUID) into the document; Mongo `_id` is internal and not the storyboard id.
- Persist `tiles` as stored JSON (array of objects); do not destructure `action` into typed fields —
  keep it opaque so forward-compat holds.

## Validation limits (mirror DialogScript style)
```
MAX_STORYBOARD_TITLE  = 256    // chars
MAX_STORYBOARD_NOTES  = 16384  // chars
MAX_STORYBOARD_TILES  = 200
MAX_TILE_LABEL        = 256    // chars
```
`title` required non-empty; `tiles` must be an array (may be empty during authoring — empty is valid).

## Files to create (mirroring DialogScript)
- `src/model/Storyboard.h` (+ `.cpp` if needed) — struct + caps + oatpp DTOs (`StoryboardDto`,
  `StoryboardTileDto`; keep `action` as an opaque `oatpp::Any`/raw-JSON field or a `String` holding
  serialized JSON — whichever preserves unknown keys best).
- `src/server/ws/dto/StoryboardRequestDto.h` — `UpsertStoryboardRequestDto` (title/notes/tiles).
- `src/server/ws/controller/StoryboardController.h` — the 5 endpoints, tracing wrapper, cache
  invalidation on mutate.
- `CacheType` additions for `storyboard-list`.
- Register the controller where `DialogScriptController` is registered.
