# World Viewer Manual

World Viewer is the wizard's window on Creature World: a macOS app that watches a world live and
shows, without a terminal, exactly what the world has sequenced, what it believes, what it has
promised itself, and what it decided to do with each of Beaky's turns. It is **read-only by
construction** — there is no write path in the app, so it can be pointed at production without a
second thought.

Issue: [#101](https://github.com/opsnlops/creature-console/issues/101) (VW-010). Plan:
[`world-viewer-plan.md`](world-viewer-plan.md). Design: [`beakys-world.md`](beakys-world.md).

## Running it

Open `Creature Console.xcodeproj`, choose the **World Viewer** scheme, and run (⌘R). Settings
(⌘,) hold the connection:

| Setting | Meaning | Default |
| --- | --- | --- |
| Address / Port / Use TLS | The Creature World to watch (fuzzball is `10.69.66.1:8001`; production is `server.prod.chirpchirp.dev:443` with TLS) | `127.0.0.1:8001` |
| Conversation ID | Which conversation the Conversation panel follows | `conversation:april-beaky` |
| Use Proxy / Proxy Host / API Key | Reach the world from outside the LAN through the ingress proxy; the key is the app-family Keychain item shared with Creature Console and Beaky Communicator | off |

The Viewer keeps its own settings (`worldViewer*` keys), so it can watch fuzzball while Beaky
Communicator on the same Mac talks to production. Changing any setting reconnects immediately.

The Viewer needs Creature World **`0.3.0`** or newer for the Conversation panel's delivery
records; everything else works against `0.2.x`.

## What you see

The sidebar lists the panels with live counts, and its footer shows where the Viewer is looking:
the stream state, the World's `build_version` and MongoDB state from `/world/v1/health`, the
latest sequence, and the world URI.

**Stream state** is the World's own vocabulary: *Connecting*, *Live*, *Resuming after N* (the
World restarted; the Viewer reconnected with `Last-Event-ID` and received the gap), *Taking a new
snapshot* (the World sent `resnapshot_required`), or *Retrying: …* with the error.

### Timeline

Every world event, newest at the top, seeded from the snapshot (the newest 2,000 events) and
advanced live from `/world/v1/stream`. Each row shows the world sequence, event type, epistemic
state and confidence, subjects, source, when it occurred, and the **lag** between `occurred_at`
and `received_at` (orange when over two seconds). Rows with a trace context show a small
trace icon. The search field filters by type, subject, or source.

### Conversation

The conversation as the World holds it — April's turns and Beaky's, newest at the top. Beneath
each of Beaky's turns is the router's **delivery chip**: the route it chose (`communicator` or
`physical_speech`), its reason (`presence_uncertain`, `confidently_away`, `home_and_audible`),
the presence it saw (state, confidence, its basis — `assumed` until real evidence exists —
and audible or not), and the outcome: `performed` when Beaky spoke in the room, `accepted` for
the Communicator, or `failed: <error_code>`. Hover for the attempt ID, decision time, and the
Creature Server animation ID of a performance. A turn with no chip was cast by hand or
pre-dates the router. This panel refreshes whenever the conversation stream announces a new
item.

### Characters

The flock as the world sees it: every character's most recent login — active (green), expired
(orange, the heartbeat stopped), or logged out — with its region, the host and pid of the mind
holding it, the `creature-agent` version, when it logged in, and its last heartbeat. The
sidebar badge counts the active ones. Refreshed when `character.logged_in` /
`character.logged_out` events arrive and on demand.

### Scenes

Every scene the world has run, newest first: what set it off, who was in the room, who holds the
floor and until when (orange while open), each character's line or pass in order, why the scene
closed, and how it was performed (the Creature Server job, or a red failure code). Refreshed on
every `scene.*` event, so you can watch the floor move between Beaky and Mango as they compose.

### Facts and Timers

What the World currently believes, and what it has scheduled. Both are seeded from the snapshot
and updated from stream deltas; the toolbar's refresh re-reads them. Until the first reducer
lands, Facts is empty and says so — the Viewer never invents a fact to fill the space.

### Mundane view

Select anything in any panel and the inspector shows it as the JSON the World actually carries
(pretty-printed, keys sorted). Toggle it with the `{}` toolbar button. This is the mundane view
of a spell: the record with the magic taken out, for when you need to see the wires.

**Scry again** in the toolbar drops the connection and starts over with a fresh snapshot.

## How it follows the world

`WorldStore` is the app's single `@MainActor @Observable` model. It runs two tasks:

1. **World stream.** Health check, then `/world/v1/stream`. A snapshot seeds facts and timers
   and triggers a bounded history read (`/world/v1/events`) for the timeline; events and deltas
   append and apply `changed_facts`. If the stream ends, the Viewer resumes after the last
   sequence it saw; if the World says `resnapshot_required`, it reconnects with no cursor. Events
   already seen are ignored, so a resume never doubles a row.
2. **Conversation stream.** `/world/v1/conversations/{id}/stream` wakes a refresh of the items and
   deliveries pages. Beaky's turns arrive here — her mind posts through the router, and the
   router publishes the canonical item to conversation subscribers — not on the world stream.

The store is an in-memory window, not a cache of record: quitting forgets everything, and the
next launch takes a fresh snapshot. The typed client lives in `CreatureAppSupport`
(`WorldViewerClient`) so a future iOS or CLI viewer reads the same way.

## Tests

- `World Viewer Tests/WorldStoreTests.swift` drives the store against a scripted world: snapshot
  seeding and the 2,000-event bound, resume without gap or repeat, `resnapshot_required`
  handling, and the join of Beaky's turns to delivery records by `response_id`.
- `Common/Tests/CreatureAppSupportTests/WorldViewerClientTests.swift` covers request shapes,
  proxy headers, and SSE frame parsing.
- `Common/Tests/CreatureWorldTests` covers the deliveries route and its paging.

Run the app tests with the **World Viewer** scheme (⌘U), or:

```bash
xcodebuild test -project "Creature Console.xcodeproj" -scheme "World Viewer" -destination "platform=macOS"
```

## Not yet

Entities, provenance and *Why?* (VW-011 #102), Honeycomb trace links (needs a URL template
setting), and any write path. The Viewer will never cast a spell; it only scries.
