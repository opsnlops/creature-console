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
| Conversation | The newest 500 items of the conversation, followed live. The history is served oldest-first a page at a time; before `0.7.1` only the first page was ever read, so a conversation past 500 items froze in the panel | |
| (health corner) | Beneath the world's version: the Information Bridge's heartbeat, green with "heard N minutes ago" while the world holds it, orange with "not heard from since …" once it has expired (`0.7.1`) | |
| Address / Port / Use TLS | The Creature World to watch (fuzzball is `10.69.66.1:8001`; production is `server.prod.chirpchirp.dev:443` with TLS) | `127.0.0.1:8001` |
| Conversation ID | Which conversation the Conversation panel follows | `conversation:april-house` |
| Use Proxy / Proxy Host / API Key | Reach the world from outside the LAN through the ingress proxy; the key is the app-family Keychain item shared with Creature Console and Flock Communicator | off |

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
trace icon; a percept that carried facts to a mind (an utterance or a floor offer) shows
**knows N** — Scry it and the Mundane view lists exactly those facts under `world_facts`. The
search field filters by type, subject, or source.

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
holding it, the `creature-agent` version, **the model the mind is thinking on**
(`local/mistral-nemo`, `openai/gpt-6-astra`; agent `2.61.1`, World `0.7.3`), when it logged in, and its last
heartbeat. The sidebar badge counts the active ones. Refreshed when `character.logged_in` /
`character.logged_out` events arrive and on demand.

### Scenes

Every scene the world has run, newest first: what set it off, who was in the room, who holds the
floor and until when (orange while open), each character's line or pass in order, why the scene
closed, and how it was performed (the Creature Server job, or a red failure code). Refreshed on
every `scene.*` event, so you can watch the floor move between Beaky and Mango as they compose.

While the room is still saying the last line, the scene's header shows in orange who is next
and when the world expects the room to finish. A line still being composed shows in orange under the turns — the sentences the room has
heard so far, ending in "…" — until the mind says it is done and it becomes a turn.

### Facts and Timers

What the World currently believes, and what it has scheduled. Both are seeded from the snapshot
and updated from stream deltas; the toolbar's refresh re-reads them. Since World `0.7.0`,
Facts holds who is logged into which region, April's assumed presence, and the room's last
scene; a superseded fact leaves the list the moment its replacement arrives. When the world
knows nothing, Facts is empty and says so — the Viewer never invents a fact to fill the space.

**Meanings** (`0.2.0`) is the panel's other mode, and Wizard Mode's first cast: the world's
glossary of what each kind of fact means to the minds (`fact_kinds`, seeded by the world from
its own catalogue). Edit a line in place and it is cast on return or when focus leaves; the world
records who reworded it and never overwrites a Wizard's words with its catalogue again. New words
— predicates the world currently believes something under but has no meaning for — sit at the top
waiting to be taught; until they are, the minds see them with no meaning attached.

### When a bird learns

A `facts.given` event cast by a mind shows on the Timeline as "Beaky learned: person:jesse
visitor.expected = "Tuesday afternoon, to finish the deck"" in mint, with a **Forget** button
(`0.5.0`): it casts nothing in its place, valid for a second, so the world believes it no longer.

### When a bird remembers the day

The nightly memory (`0.6.0`; World `0.22.0`, agent `2.71.0`) shows as "Beaky remembered the day:
5 episodes" in indigo on the Timeline once the job has run (3:30 by default). The episodes
themselves are facts — `memory.episode.<day>.<n>` on each person, place, or bird they concern and
`memory.reflection.<day>` on the bird — and read like any other fact on the Facts tab, under the
`memory.episode` / `memory.reflection` families in Meanings. They carry no expiry; retention never
removes them. **Beliefs** (`0.8.1`; World `0.31.0`, agent `2.73.0`) — what the month's episodes
settled into, `memory.belief.<n>` — show on an entity's page under **Come to believe**, above
**Remembered**; a bird's `self` beliefs are on the bird's own page. Why? on a belief shows the
consolidation run that wrote it; the days it rests on are in its value.

### Entities

The **Entities** panel (`0.7.0`) is the world one hub at a time: pick any subject the world
believes something about, type an id (`person:jesse`), or right-click a fact anywhere → **Show
person:jesse** (a fact whose value is an entity also offers to show *that*). The page lists the
entity's facts — the ones the birds are handed in the normal colour, world-only ones in grey with
a "world only" tag — links as buttons that open the other entity, what points at this one,
what the birds remember about it, and the last week of its events. Forget works here too. The
Mundane view carries the whole page as the world returned it.

### Audience

Every meaning on the Meanings tab has a picker: **minds** (handed to the birds, the default) or
**world only** (kept and shown, used by the world's rules, never put in a prompt). A phone number
is world only; a birthday is not. The choice is cast into the glossary as a Wizard's word.

### Why?

Right-click any fact — on the Facts tab or an entity's page — → **Why?** (`0.8.0`, VW-011):
a sheet with the fact, then *because the world was told* — each event behind it with its type,
who told the world, when, and its whole payload — then the facts it was derived from and, for
a fact that has been replaced, what superseded it. A `visitor.expected` on the house walks
back to the Bridge's `facts.given` from the mail; a `presence.state` to the house's
`camera.person_seen`; a bird's memory to the day it remembered. The same walk as WorldMCP's
`explain_fact` (`GET /v1/facts/{id}/explain`, world `0.30.1`). A fact the world has already
let go of says so instead of a sheet of nothing.

### Forgetting a fact

Right-click any fact on the Facts tab → **Forget** (`0.6.1`): the same retraction as the
Timeline's Forget button, for any fact the world believes — a bird's memory it filed wrongly, a
learned thing April did not mean it to keep. The fact shows as `null` for a second and then
leaves the list on its own (`0.6.2`): the world sends no delta when a window closes, so the
Viewer keeps its own alarm for the soonest expiry.

### When a bird passes

A pass in a scene shows its reason in grey — "passes: Beaky already asked April", "passes: joke
already landed" (`0.4.1`; agent `2.69.0` gives one on every pass). A scene that closes
`everyone_passed` after a couple of good lines is the design working, not a fault.

### When the house asks

A scene's trigger carries a symbol: April spoke, the house told (`house.fill`), or the house
asked (`questionmark.bubble`). When the lead judged a question not worth a word, the scene
closes as `declined` and the row says who "considered it and stayed quiet" and why; the
Timeline shows the same on its `house.remark_declined` event. A quiet decision is a decision,
shown in grey, never in red.

### When something fails

A turn the room could not speak shows its delivery chip in red with the reason beneath it, in
the refusing service's own words — "Creature 4754fc0e… is not registered with a universe. Is
the controller online?" rather than `physical_speech_start_failed` alone (`0.3.0`; the reason
is recorded by World `0.19.0` and agent `2.67.0`, so older records show only the code). A scene
whose room could not be readied — Creature Server refused the dialog stream — is a red
`scene.stage_problem` on the Timeline the moment it opens, with the reason; a failed performance
shows it under the scene. Every trace icon is a link into Honeycomb for that trace, end to end.

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

Honeycomb trace links (needs a URL template setting), and any write path beyond Forget and
the Wizard's words. The Viewer will never cast a spell; it only scries.
