# World Viewer — First Cut Implementation Plan

**Issues:** [#101](https://github.com/opsnlops/creature-console/issues/101) (VW-010, Viewer shell);
[#102](https://github.com/opsnlops/creature-console/issues/102) (VW-011, Why?) follows.
**Roadmap:** Phase 4, pulled forward (see `beakys-world.md` §0.6).
**Status:** built on `vw-010-world-viewer`; see [`world-viewer-manual.md`](world-viewer-manual.md).
**Products:** new macOS app target **World Viewer**; Creature World `0.2.2` → `0.3.0` (one read
route added).

## Why now

On the night Beaky first spoke, every look into the world — the event stream, sequences,
percepts, the router's decisions, the traces — went through Claude's tooling. April was debugging
by proxy. April: "we also have the world viewer app to build so I can debug as well as you."
Every slice after this one (her voice in the room, facts, personalities) gets easier to build and
to trust when the world can be watched without a terminal.

## The moment

April opens World Viewer on her laptop, points it at fuzzball, types to Beaky on her phone — and
watches the utterance event arrive with its sequence number, Beaky's mind produce a turn, and the
router record *communicator / presence_uncertain / unknown presence* beside it. When the first
reducer lands, the Facts panel lights up on its own.

## Scope of the first cut

| Panel | Source | Notes |
| --- | --- | --- |
| **Connection header** | `/world/v1/health` | World URL, `build_version`, MongoDB state, stream state (connecting / live / resuming / resnapshot) |
| **Timeline** | `/world/v1/stream` (snapshot, then `Last-Event-ID` resume), `/world/v1/events` for history paging | Every event: sequence, type, subjects, source, occurred/received and the lag between them; filter by type/subject text; select for an inspector with the raw JSON |
| **Conversation** | `/world/v1/conversations/{id}/items` + **new** `…/deliveries` | Both authors in order; per Beaky turn: route, reason, the presence the router saw (state/confidence/audible), outcome state, attempt ID |
| **Facts** | `/world/v1/facts` | Empty today by design; refreshed from stream deltas' `changed_facts` |
| **Timers** | `/world/v1/timers` | Pending / firing / fired / canceled |

Deliberately **not** in this cut: entities, provenance / Why? (VW-011), Honeycomb links (needs a
URL template setting — small follow-up), any write path. The Viewer is read-only, as §12 requires.

## Design

### Creature World: `GET /world/v1/conversations/{conversation_id}/deliveries`

The router already persists `StoredCharacterDelivery` (intent, decision, outcome, canonical item)
in `character_deliveries`; nothing reads it back. Add a bounded, paginated read
(`after_response_id`, `limit`) through the application-service boundary. The wire shape is a new
snake_case DTO in `WorldCore` (`CharacterDeliveryRecord` / `CharacterDeliveryPage`) built from the
stored record — the stored document keeps its current field names so existing rows decode.

### CreatureAppSupport: `WorldViewerClient`

Typed, injectable (`HTTPDataLoading`, like `WorldConversationClient`), macOS/iOS only:
`health()`, `events(after:limit:)`, `facts(subject:after:limit:)`, `timers(status:after:limit:)`,
`conversationItems(in:after:limit:)`, `deliveries(in:after:limit:)`, and
`eventStream(resumeAfter:)` — an `AsyncThrowingStream<WorldStreamFrame>` parsing `snapshot`,
`event`, `delta`, and `resnapshot_required` frames from `URLSession.bytes`. The wire DTOs
(`WorldHealth`, pages, `WorldSnapshot`, `WorldDelta`) moved from `creature-world` into `WorldCore`
so the server, the agent, and the apps decode one definition.

### The app

- **Target** `World Viewer` (macOS only, `io.opsnlops.World-Viewer`), a file-system-synchronized
  group at `World Viewer/`, package products `WorldCore` + `CreatureAppSupport`, cloned from the
  Beaky Communicator target's pbxproj entries under a fresh ID prefix.
- **Connection settings** mirror Beaky Communicator (`CreatureServiceSettings` + the app-family
  Keychain proxy key) under their own `worldViewer*` UserDefaults keys, so dev and prod are
  separate worlds.
- **`WorldStore`** (`@MainActor @Observable`): connection state, a bounded ring of events (2,000
  newest, snapshot-seeded, gap-free resume), facts, timers, conversation items and deliveries
  keyed by item / response ID. In-memory for the first cut: this is a debugging window, not a
  cache of record; SwiftData persistence can come with VW-011 if replay needs it.
- **UI**: `NavigationSplitView` — sidebar of panels, content list, trailing inspector with raw
  JSON. Liquid Glass surfaces per house style; Timeline rows show sequence · type · subjects ·
  lag; Conversation rows show author bubbles with a glass "delivery" chip on Beaky's turns.

### Tests

- `CreatureWorldTests`: deliveries route paging and 400s; DTO round-trip fixture.
- `CreatureAppSupportTests`: `WorldViewerClient` request shapes and SSE frame parsing with a stub
  loader (snapshot → deltas → `resnapshot_required`; `Last-Event-ID` header on resume).
- `World Viewer Tests`: `WorldStore` against a scripted world through the `WorldScrying` seam —
  ring bounds, resume without gap, `resnapshot_required`, delivery join by `response_id`.
- Xcode build of the new target in CI (`tests.yml` matrix gains the scheme).

## Exit

World Viewer connects to fuzzball and shows: the live timeline advancing as April types on her
phone; the conversation with Beaky's turns annotated by the router's decision; empty Facts and
Timers panels that are honest about it; and a resume without gap after the World restarts.
