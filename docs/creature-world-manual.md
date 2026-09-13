# Creature World Manual

Creature World is the authoritative shared-world simulator for April's Creature Workshop. It is a
headless Swift service that owns durable world events, current facts, timers, and source ingestion
checkpoints. This manual describes the software that exists today. The broader design and roadmap
remain in [Beaky's World](beakys-world.md).

## Current service boundary

Creature World is one product in the `creature-console` monorepo, not another mode of Creature
Console and not part of `creature-server`. It has its own:

- executable and version (`creature-world`);
- Debian package (`creature-world_<version>_<architecture>.deb`);
- JSON configuration;
- systemd unit;
- MongoDB database (`creature_world`);
- health and readiness lifecycle.

The service exposes a versioned JSON API for event ingestion, durable queries, snapshots, and a
live Server-Sent Events (SSE) stream. HTTP handlers call one application-service boundary shared
with future transports; they never access MongoDB directly.

## Quick start for development

The repository pins MongoDB 8.3.8 and configures it as a single-node replica set:

```bash
docker compose -f compose.creature-world.json up -d
cd Common
swift run creature-world
```

The Compose project persists MongoDB data in its `mongodb-data` volume and initializes a replica
set named `creature-world`. The default service address is `http://127.0.0.1:8001`.

Check readiness with:

```bash
curl --fail-with-body http://127.0.0.1:8001/world/v1/health
```

A ready response is HTTP 200:

```json
{
  "status": "ok",
  "schema_version": 1,
  "build_version": "0.6.2",
  "service": "creature-world",
  "mongodb": "ok"
}
```

Stop the development database without deleting its data:

```bash
docker compose -f compose.creature-world.json down
```

Adding `--volumes` to that command deletes the development database. Do that only when a clean
database is intentional.

## Configuration

Creature World uses JSON configuration. Configuration precedence, from highest to lowest, is:

1. Command-line options.
2. Environment variables.
3. The JSON configuration file.
4. Built-in defaults.

The configuration file is selected with `--config` or `CREATURE_WORLD_CONFIG`. The packaged
systemd service reads `/etc/creature/world.json` by default.

| Setting | JSON key | Environment | Command option | Default |
| --- | --- | --- | --- | --- |
| HTTP host | `host` | `SERVER_HOSTNAME` | `--host`, `-H` | `127.0.0.1` |
| HTTP port | `port` | `SERVER_PORT` | `--port`, `-p` | `8001` |
| MongoDB URI | `mongodb_uri` | `MONGODB_URI` | `--mongodb-uri` | Local replica set |
| Browser stream origins | `allowed_origins` | `CREATURE_WORLD_ALLOWED_ORIGINS` | — | None |
| Assumed presence | `presence.assumed` | — | — | None (presence is `unknown`) |
| Creature Server for scenes | `creature_server.url` (+ `proxy_host`, `api_key`) | — | — | None (scenes are recorded as `creature_server_not_configured`) |
| Lead character | `lead_character` | — | — | `character:beaky` (who an unaddressed message goes to) |
| Scene performance | `scene_performance` | — | — | `streaming` (`complete` renders the whole scene at once) |
| Regions → stages | `regions.<region_id>.stage_id` | — | — | None (streaming falls back to the complete render) |
| Scene cutoffs | `scenes.floor_seconds`, `scenes.maximum_turns`, `scenes.maximum_spoken_seconds`, `scenes.words_per_second` | — | — | `8`, `12`, `90`, `2.5` |

Example:

```json
{
  "host": "127.0.0.1",
  "mongodb_uri": "mongodb://127.0.0.1:27017/creature_world?replicaSet=creature-world&directConnection=true&connectTimeoutMS=5000",
  "port": 8001
}
```

### Assumed presence

Until a presence source exists (VW-006/VW-013), the world can be told to *assume* where a person
is. This is what puts Beaky's voice in the room today:

```json
{
  "presence": {
    "assumed": {
      "person:april": { "state": "home", "physically_audible": true, "confidence": 0.9 }
    }
  }
}
```

`state` is `home`, `away`, or `unknown`; `physically_audible` defaults to `false`; `confidence`
defaults to `1` and must reach the router's minimum (`0.8`) for the assumption to choose a
stage. Every decision made on an assumption records the presence with `basis: assumed`, so
World Viewer shows exactly why a turn went where it did. Remove the block and the next turn goes
back to the Communicator with `presence_uncertain`; nothing else changes. People without an
entry are `unknown`.

`--log-level` controls log verbosity and defaults to `debug`. Supported values are `trace`,
`debug`, `info`, `notice`, `warning`, `error`, and `critical`.

`CREATURE_WORLD_ALLOWED_ORIGINS` is a comma-separated list of exact origins.

Run `creature-world --help` for the complete command-line reference.

## MongoDB decisions

### Version and topology

Creature World standardizes on MongoDB 8.3, currently pinned to 8.3.8 in development and CI. It
requires a replica set, including for single-node development. This gives the service the MongoDB
semantics needed for majority writes and a production-shaped local environment.

The default development URI is:

```text
mongodb://127.0.0.1:27017/creature_world?replicaSet=creature-world&directConnection=true&connectTimeoutMS=5000
```

`directConnection=true` is appropriate for the single-node local setup. A production URI should
describe the deployed replica set or managed MongoDB cluster instead.

### Addressing

Who April is talking to is a world rule (`0.6.2`, refined in `0.7.0`), so typed words and
spoken ones later are addressed the same way. At ingress the world looks at the start of the
message:

- **A whisper, "@beaky …"** — an @-name of a character who is logged in is for that character
  **alone**: it answers by itself and no scene opens, so April can have a word with just her
  familiar.
- **A name, "Beaky, …" / "Hey Kenny …"** — that character answers **first**; if others are
  logged in the world opens a scene so they may chime in (April: "I'm kinda liking the way
  everyone else chimes in when I say I love Beaky").
- **Anything else** is for the room: it goes to the lead (`lead_character`, default
  `character:beaky`) first, and likewise opens a scene when others are present.

The sender's addressee (the app always says Beaky) is only a hint; the utterance is stored as
sent and the percept carries the world's choice, with `conversation.addressee.alone` on the
ingest span. A name mentioned later in the sentence ("I think Mango is right") does not
redirect it. `conversation:april-house` is the house conversation (from Communicator
`0.3.0` and Viewer defaults): every character speaks in it. `conversation:april-beaky` holds the
history from before the flock and stays readable.

### Scenes

When April speaks to a character while other characters are logged into the same region, the
world does not let the addressee answer alone: it opens a **scene** and gives the floor to one
character at a time — the addressee first, then the others in a round — with a
`scene.turn_offered` event for each offer. A mind answers with a line or a pass through
`POST /world/v1/scenes/{scene_id}/turns`; a floor nobody answers by `floor_seconds` is a pass
(the deadline is a world timer, `scene.floor_expired`). The scene closes when everyone passes in
a row, at `maximum_turns`, or when the composed speech would exceed `maximum_spoken_seconds`
(estimated at `words_per_second`); a new scene in the region interrupts an open one. Every spoken
turn is also a conversation item, so the Communicator shows the exchange as it is composed.

**The house opens scenes** (`0.10.0`, F3): `scenes.open_on` lists the world events that
start a scene on their own, where, and how often —

```json
"scenes": { "open_on": [
  { "event": "camera.person_seen",  "places": ["place:driveway", "place:front-door", "place:carport"], "cooldown_seconds": 300 },
  { "event": "camera.vehicle_seen", "places": ["place:driveway", "place:carport"], "cooldown_seconds": 300 },
  { "event": "door.unlocked", "cooldown_seconds": 60 }
] }
```

— the MQTT agent's areas and cooldowns, as world rules. When a matching event is accepted
(and its place has not opened one within the cooldown), the world opens a scene in the
region whose `places` include it (a person's event uses the lead's region), in
`house_conversation` (default `conversation:april-house`), with the lead first and everyone
else logged into the region after; the trigger is a stage note the birds read — "A person
was just seen at the driveway." — and Beaky, as lead, speaks first. Nobody logged in means
no scene. The rest is the ordinary scene machinery, including the facts on each floor offer
(so the birds also know it is 66 degrees and the cameras are otherwise quiet).

**A line may arrive sentence by sentence** (`0.9.0`, #175): a mind with a streaming model
submits `{ "text": "Not quite, Kenny.", "piece": 0 }`, `{ …, "piece": 1 }`, … and finally
`{ "text": null }` (or a last sentence with no `piece`) for "that was the whole line". Each
piece is spoken the moment it lands (`scene.turn_piece`; the streaming performer sends it as
a `dialog-stream` turn — creature-server#192 asks for a `continues` flag so consecutive pieces
keep the pose and prosody), the floor's deadline moves out by `floor_seconds` with each, a
stale floor timer is ignored, a retried piece is a `duplicate`, and the pieces are joined
into one turn — recorded once — when the line is done. A line that goes quiet becomes the
line so far when the floor expires. This is what lets a frontier model's longer line start
playing after its first sentence instead of its last.

Two ways to the room, chosen by `scene_performance`:

- **`streaming`** (default; Creature Server 3.46.0+, creature-server#186): when the scene opens
  the world opens a `dialog-stream` session for the participants on the **stage the region maps
  to** (`regions.<region>.stage_id`; the server needs placements so the birds look at each
  other), sends each spoken turn the moment it is composed — it plays ~2 s later while the next
  bird is still thinking — and on close calls `finish`, which waits for the last turn to play
  and stitches the exchange into one ad-hoc animation (recorded as the performance). Turns are
  single-voice renders. If the session cannot be opened (a controller offline, a participant not
  placed on the stage, no stage mapped for the region) the scene falls back to the complete
  render below, so it is still heard.
- **`complete`**: the closed scene is rendered as one jointly conditioned performance through
  the ad-hoc dialog pipeline (`POST /api/v1/animation/dialog`, `persistence: "adhoc"`,
  autoplay); the server's job ID is recorded as `queued`. Slower to start, but the voices react
  to each other in tone.

Each character speaks through the creature its mind logged in with. Without `creature_server`
configured the scene is recorded as `abandoned` with `creature_server_not_configured`, visible
in World Viewer's Scenes panel, never lost. A scene with no words is `abandoned` without a
render. Events: `scene.opened`, `scene.turn_offered`, `scene.turn`, `scene.closed`,
`scene.performed`.

```json
{
  "creature_server": { "url": "https://server.prod.chirpchirp.dev" },
  "scene_performance": "streaming",
  "regions": { "region:home": { "stage_id": "0300c6eb-bbc8-4f31-9ffb-f46501d9c5d4" } },
  "scenes": { "floor_seconds": 8, "maximum_turns": 12, "maximum_spoken_seconds": 90 }
}
```

**The packaged `world.json` is April's real configuration** — Creature Server's URL, the
assumed presence, `region:home` with its stage and places, the given facts — so that when an
upgrade changes the file and dpkg asks which version to keep, either answer works. (On
2026-09-12 the package's copy won and it had no `creature_server`; every scene then failed
with `creature_server_not_configured` until the block was put back.) Stages come from
`GET /api/v1/stage` on Creature Server. The packaged `world.json` maps
`region:home` to **Mainstage** (`0300c6eb-bbc8-4f31-9ffb-f46501d9c5d4`), which has every bird
placed on it; the characters' new building will get its own region and stage when it exists.

### Facts: what the world knows

From `0.7.0` the world turns what it sees into **facts** (`fact` records: subject, predicate,
value, epistemic state, validity window, provenance back to the event) through pure reducers
run on the authoritative event loop, and tells the minds about them. The first reducers:

| Event | Fact | Epistemic |
| --- | --- | --- |
| `character.logged_in` / `logged_out` | `character:<x>` `presence.region` = `region:home` (or `null` on logout) | observed, 1 |
| `character.logged_in` with `pronouns` (the mind's persona, `0.7.2`) | `character:<x>` `identity.pronouns` = `he/him`; outlasts the login | observed, 1 |
| `presence.assumed` (announced from `presence.assumed` in `world.json` at startup, idempotent) | `person:april` `presence.state` = `home`, `presence.physically_audible` = `true` | assumed, configured confidence |
| `scene.performed` | `region:home` `scene.last` = trigger and lines, valid for one hour | observed, 1 |
| `facts.given` (each entry of `facts` in `world.json`, announced at startup, idempotent; `0.7.3`) | as stated, e.g. `person:polly` `person.description` = `April's sister` | reported, 1 |
| `door.locked` / `door.unlocked`, `door.opened` / `door.closed` (from `creature-house`, `0.8.0`) | `place:<door>` `door.lock` / `door.state` | observed, 1 |
| `motion.detected` / `motion.cleared` | `place:<room>` `motion.active` (true for ten minutes) | observed, 1 |
| `camera.person_seen` / `vehicle_seen` / `animal_seen` | `place:<camera>` `seen.person` / `seen.vehicle` / `seen.animal`, ten minutes | observed, 1 |
| `camera.watching` (`0.8.2`) | `place:<camera>` `camera.watching` = true, so nothing seen is a fact | observed, 1 |
| `person.arrived` / `person.left` | `person:<x>` `presence.state` = `home` / `away` — **supersedes the assumption; the router reads it first** | observed, 1 |
| `environment.measurement_changed` | `place:<x>` `environment.<predicate>` = number | observed, 1 |
| `house.scenes_offered`, `house.scene_requested`, `house.scene_activated` | `house:<x>` `house.scenes`, `house.scene_requested` (two minutes), `house.scene` | observed, 1 |

`facts` in `world.json` is for things April simply states until a source can observe them —
who a person is, mostly — and is deliberately thin: a `person.description` is phrased to the
minds as "Polly is April's sister. That is all you know about Polly; do not make up more."
Details (where she lives, her birthday) should come from the address book through the
Information Bridge, which will supersede these.

```json
"facts": [
  { "subject_id": "person:polly", "predicate": "person.description", "value": "April's sister" }
]
```

A newer fact about the same subject and predicate **supersedes** the older one: the old
document gets `valid_to` and `superseded_by`, so `GET /world/v1/facts` and the Viewer's Facts
panel always show the current world and the history stays queryable. `regions.<region>.places` lists the places
(and the house) whose facts the characters in that region are told about. The world also
**sweeps expired character sessions** every 15 s and announces the logout itself, so a mind that died
without saying goodbye leaves the room in the facts too.

Every percept a mind receives carries `world_facts`: the current facts (newest first, at most
40) whose subject is the addressee, the region it is in, everyone logged into that region, or
the speaker. `PersonUtterancePercept` gets them at ingress and `SceneTurnOffer` gets them with
each floor offer, so both are in the event payload and visible in the Viewer's Mundane view —
the Timeline row shows **knows N** for any percept that carried facts. Minds never fetch facts;
they are told (`docs/facts-and-personas-plan.md`).

### Local Debian builds under the upgraded Docker Desktop

After Docker Desktop's 2026-09-11 self-update (engine 29.7.2, kernel 7.0.12-linuxkit),
`./build_debs.sh --arch amd64` hangs inside the container: `swift-build` parks in a mutex wait
with defunct `git` children under Rosetta, sometimes on the first product, sometimes the second.
The same kernel refuses to run MongoDB 8.3 (`SERVER-121912`; only kernels 7.0.14+ are fixed).
Until Docker ships a newer kernel, take Linux packages from the `build-deb` GitHub Actions run
for the commit (`gh run download <run-id>`), and run the local MongoDB replica set on `mongo:7`
(`docker compose -f compose.creature-world.json -f <override with image: mongo:7 and its own
volume> up -d`).

### MongoKitten fork

`Common/Package.swift` pins MongoKitten to the `opsnlops/MongoKitten` fork (tag
`7.16.3-opsnlops.1`, branch `fix/end-cursor-spans` on top of `7.16.3`) until the change lands
upstream. Upstream
starts a `Find<…>` / `Aggregate<…>` / `ListIndexes<…>` / `ListCollections` span for every cursor
operation and never ends it, so in Honeycomb every `MongoKitten.Find<…>` and `.getMore` span in a
World trace hung from a parent that never arrived. The fork makes the cursor own that span and end
it when the cursor is exhausted, closed, or released. Move the pin back to
`orlandos-nl/MongoKitten` once a release contains the fix.

### Database isolation

The database name is always `creature_world`. Creature Server uses `creature_server`; the two
services do not share a database merely because they live in related repositories or participate
in the same workshop system.

Creature World rejects a MongoDB URI that omits the database or selects any database other than
`creature_world`. This guard prevents an operator from silently writing world state into another
service's database.

### Startup during an outage

MongoDB availability is a readiness dependency, not a process-liveness dependency:

1. Creature World resolves and validates its configuration.
2. It attempts the initial MongoDB connection and schema preparation.
3. If MongoDB is unavailable, it logs a warning and continues starting the HTTP server.
4. The background persistence service retries on a five-second cadence.
5. When MongoDB returns, Creature World reconnects, ensures the schema, logs the recovery, and
   becomes ready without a process restart.

Connection selection and timeout behavior can add time to the retry cadence. Repeated failures are
logged at debug level after the first warning so an outage remains diagnosable without flooding
normal logs.

Invalid local configuration remains a startup error. Examples include an invalid port, malformed
MongoDB URI, or a URI selecting the wrong database. Authentication, connectivity, or schema
preparation failures leave the running service unready until they are corrected.

### Health semantics

`GET /world/v1/health` is a readiness check:

- HTTP 200 with `status: "ok"` and `mongodb: "ok"` means the required schema record is readable.
- HTTP 503 with `status: "unavailable"` and `mongodb: "unavailable"` means callers must not send
  work that depends on persistence.

An HTTP 503 does not mean the process should be restarted. Supervisors should use process exit for
liveness and `/world/v1/health` for readiness. This distinction allows Creature World to survive a
MongoDB restart or temporary network outage and recover in place.

Example unavailable response:

```json
{
  "status": "unavailable",
  "schema_version": 1,
  "build_version": "0.6.2",
  "service": "creature-world",
  "mongodb": "unavailable"
}
```

### Collections and indexes

Schema migrations 1 through 8 establish the following collections and indexes (5:
`character_stage_decisions` with a TTL; 6: `character_sessions`; 7: `scenes`; 8: the
`predicate_subjects` index on `facts`):

| Collection | Purpose | Important indexes |
| --- | --- | --- |
| `world_events` | Immutable accepted world events | Unique `event_id`; unique `world_sequence`; unique source ID plus source event ID when present; event type/time; subject IDs |
| `world_event_processing` | Durable completion markers for accepted events | Unique event ID in `_id` |
| `world_counters` | Atomic sequence allocation | `_id: "world_sequence"` counter document |
| `facts` | Durable facts and current-state reads | Unique `fact_id`; active facts by subject, predicate, validity, and supersession; `predicate_subjects` (predicate, supersession, validity, subject) for "who does the world describe?" |
| `timers` | Durable simulator timers | Unique `timer_id`; recoverable timers by status and due time |
| `source_checkpoints` | Per-source cursor or checkpoint state | Unique `source_id` |
| `utterance_ingresses` | Durable, idempotent person-utterance processing records | Unique utterance ID |
| `conversation_items` | Canonical conversation history shared by clients and characters | Unique item ID; conversation/time/item order |
| `character_deliveries` | Durable delivery decision and outcome for each character turn, keyed by `response_id` | Unique `decision.attempt_id`; conversation/time order |
| `schema_migrations` | Applied Creature World schema versions | Migration version in `_id`; current migration is 8 |

The migrator is idempotent and runs whenever a connection is established. Writes use majority write
concern.

MongoKitten represents BSON documents and arrays with the same `Document` type and distinguishes
them with `isArray`. Creature World therefore reconstructs dynamic `WorldJSONValue` payloads at
the repository boundary instead of relying on MongoKitten's permissive Codable decoder, which can
discard object keys or mistake arrays for objects. Event, fact, timer, and source-checkpoint tests
cover nested objects and empty arrays. Typed person-utterance percepts are decoded again after a
MongoDB round trip, not merely compared before persistence.

Event ingestion is idempotent in two ways:

- Reusing an `event_id` returns the event already accepted.
- Reusing a source ID and source event ID returns the event already accepted.

`world_sequence` is allocated atomically and is unique and increasing. It is not promised to be
gap-free: a sequence may be allocated before an insert loses a deduplication race or fails.
Consumers must order by the value, not infer missing events from a gap.

Current facts are records where both `valid_to` and `superseded_by` are null. They are stored in
MongoDB, so reconnecting or restarting Creature World does not erase the current world state.

### Durable time and timers

Domain code uses the injected `WorldClock`; it does not read wall-clock time directly. Production
uses `SystemWorldClock`. Deterministic tests and future replay use `ManualWorldClock`, whose time is
advanced explicitly and whose sleeps are cancellable. Timer tests never wait for real time.

Timer IDs are stable semantic keys such as
`timer:calendar-event-123:departure-due`. Scheduling the same key again replaces its pending
definition, so a changed due time does not leave the old wake-up active. Canceling is conditional:
only a pending timer can transition to `canceled`.

A firing uses this durable lifecycle:

1. Atomically transition the matching timer occurrence from `pending` to `firing`.
2. Submit its semantic event through the authoritative `World` actor.
3. After durable event acceptance and reduction, transition that occurrence to `fired`.

The emitted event uses the timer ID and due-time milliseconds as its stable source identity. If the
process stops after event acceptance but before the final timer update, startup recovery finds the
`firing` timer and submits the same source identity again. The immutable event log deduplicates that
retry, after which the timer can safely become `fired`. Overdue pending timers follow the same path
when MongoDB first connects or reconnects. The event records `timer_id`, `scheduled_for`,
`fired_at`, and nonnegative `lateness_ms` alongside the timer's semantic payload and provenance.

Recovery is bounded to 10,000 active timers per process. A larger set prevents readiness rather
than allocating an unbounded collection. In-memory waits are canceled during replacement,
cancellation, database disconnect, and graceful shutdown; MongoDB remains the authoritative timer
state.

## Authoritative event processing

One `World` actor is the serialization point for accepted events and deterministic reducers.
**No reducers are registered yet**: every accepted event is persisted, sequenced, and published,
but none currently produces a fact, so the `facts` collection stays empty until the first
presence reducer (VW-006) lands. Beaky's mind therefore reasons from the conversation alone. An
acceptance joins an ordered work chain, but MongoDB and fact persistence run in concurrent tasks
outside the actor. The actor therefore remains responsive while storage is suspended without
allowing a later event to overtake an earlier event.

Processing is append-first:

1. Append or deduplicate the root event and assign its authoritative sequence.
2. Run matching reducers in registration order.
3. Upsert changed facts and append derived events with `caused_by` provenance.
4. Publish ordered, at-least-once deltas to subscribers.
5. Mark the causal batch processed from descendants back to its root.

The processing marker distinguishes delivery deduplication from completed reduction. If fact
persistence or derived processing fails after event acceptance, resubmitting the same event runs
the unfinished deterministic work again. Fact upserts and deterministic derived event IDs make
that retry idempotent. Deltas are published before completion markers, and descendants are marked
before the root. If a marker write fails, a retry may therefore republish a delta but cannot hide a
previously completed descendant. Subscribers must treat event IDs as idempotency keys and obtain a
fresh snapshot after reconnecting; an in-memory delta is not a durable acknowledgement.

Reducers are synchronous and side-effect-free. They may calculate facts and proposed derived
events, but they cannot suspend for MongoDB, HTTP, model inference, or other external I/O. Those
operations belong outside the actor and return their results as later world events.

### Resource limits and subscriber behavior

The actor enforces finite defaults of 1,024 pending acceptances, 1,024 derived events in one causal
batch, 256 live subscriptions, and 256 buffered deltas per subscriber. These limits prevent a
stalled database, erroneous reducer, or collection of slow subscribers from growing memory without
bound. A full ingress queue rejects new work before acceptance. A causal batch over its derivation
limit fails while its root remains retryable. Excess subscriptions are rejected, and a subscriber
that falls behind is disconnected with an explicit resnapshot error; the service never silently
presents a lossy delta stream as complete.

### Event-processing telemetry

Creature World follows the same instrumentation style as `LocalLLMHealthCheck` in
`creature-agent`: metric instruments are initialized with the processing component and async work
is wrapped in semantic `withSpan` operations. The actor emits `world.event.accept` and
`world.event.process` spans. The off-actor task preserves task-local trace context, so the process
span remains a child of acceptance and its upstream caller.

Span attributes are restricted to controlled event, source, sequence, disposition, and lag fields.
Event payload values are never attached. Metrics cover received, accepted, rejected, duplicate,
processed, and failed events, queue depth, subscriber drops, and event lag. The HTTP boundary
extracts W3C `traceparent`, `tracestate`, and `baggage` context. Event ingress also persists a valid
incoming W3C context in the canonical envelope when the sender did not provide one there.
Malformed context is rejected before acceptance. The actor's task boundary is tested not to break
the active context.

Timer operations add `world.timer.schedule`, `world.timer.cancel`, and `world.timer.fire` spans and
counters for scheduled, canceled, fired, recovered, rejected, and failed timers. Attributes contain
only the stable timer ID, semantic purpose, disposition, and lateness; timer payload values are not
attached.

Person utterance ingestion uses the existing `conversation.utterance.ingest` span and records only
stable IDs, source, modality, boundary, and disposition. Conversation text and proxy credentials
are never attached to telemetry. The accepted `PersonUtterancePercept` becomes a typed,
source-idempotent world event so the future character agent consumes the same ordered cognition
pipeline as every other world event.

## JSON and live-stream API

All API JSON uses snake-case keys and RFC 3339 timestamps. Event requests require
`Content-Type: application/json`. Every route begins with `/world/` so ingress can route Creature
World independently from Creature Server. The canonical production health endpoint on the LAN is
`https://server.prod.chirpchirp.dev/world/v1/health`.
`https://proxy.prod.chirpchirp.dev/world/v1/health` provides access from outside the LAN. The
current endpoints are:

| Method and path | Purpose |
| --- | --- |
| `POST /world/v1/events` | Accept one `WorldEventEnvelope`; returns HTTP 202 for a new event or 200 for a duplicate. |
| `POST /world/v1/events:batch` | Accept up to 100 envelopes in request order and return a disposition for each. |
| `GET /world/v1/events` | Read ordered history after `after_sequence`. |
| `POST /world/v1/conversations/{conversation_id}/utterances` | Durably accept one typed `PersonUtterance`; returns 202 when new or 200 when already accepted. |
| `POST /world/v1/conversations/{conversation_id}/responses` | Carry one `CharacterUtteranceIntent` (a Beaky turn) into the conversation. The deterministic router reads fresh presence, persists the canonical item first, then delivers; returns 202 with `disposition: accepted` when this call handled it or 200 with `disposition: duplicate` when the same `response_id` was already handled. |
| `GET /world/v1/conversations/{conversation_id}/items` | Read canonical conversation items in chronological, stable-ID order. |
| `GET /world/v1/conversations/{conversation_id}/stream` | Receive an immediate `ready` event followed by live conversation-item notifications over SSE. Reconcile through the items endpoint after connecting. |
| `POST /world/v1/conversations/{conversation_id}/stage` | A mind asks where a turn it is about to produce should be performed: `{ "response_id", "character_id", "recipient_id" }`. The router reads presence once and persists a `CharacterDeliveryDecision` for that `response_id` (expired by MongoDB after five minutes if never used). Asking again returns the same decision; a turn already carried answers `already_delivered` with the record so it is never performed twice. Added in `0.4.0`. |
| `POST /world/v1/conversations/{conversation_id}/performances` | A mind records a turn it performed itself on a staged decision: `{ "intent", "attempt_id", "outcome": { "state": "performed" \| "failed", "provider_reference"?, "error_code"? } }`. The canonical item, decision, and outcome are stored in one step and the item is published to conversation subscribers; returns the same body as `/responses`. A performance the world never staged is refused with 400. Added in `0.4.0`. |
| `POST /world/v1/characters/{character_id}/login` | A mind logs in as a character in a region: `{ "region_id", "instance": { "host", "process_id", "creature_id"?, "version"? } }`. Returns 200 with `disposition: logged_in` (or `renewed` for the same instance) and the session; 409 with `disposition: logged_in_elsewhere` and the session that holds the character. A character is in one region at a time. Added in `0.5.0`. |
| `POST /world/v1/characters/{character_id}/heartbeat` | `{ "session_id" }` keeps the session alive (30 s lifetime); 409 `logged_in_elsewhere` once it has lapsed. |
| `POST /world/v1/characters/{character_id}/logout` | `{ "session_id" }` ends the session and frees the character. |
| `GET /world/v1/characters` | Every character's most recent session (`active`, `expired`, or `logged_out`) — the flock as the world sees it; World Viewer's Characters panel. |
| `POST /world/v1/scenes/{scene_id}/turns` | A mind answers the floor: `{ "character_id", "response_id", "session_id", "text" }` — `text` absent is a pass. 202 `accepted`, 200 `duplicate`, 409 `not_your_turn` (the floor moved on) or `logged_in_elsewhere`. Added in `0.6.0`. |
| `GET /world/v1/scenes` | The most recent scenes (`limit`), newest first: trigger, participants, floor, turns, close reason, performance. |
| `GET /world/v1/scenes/{scene_id}` | One scene. |
| `GET /world/v1/conversations/{conversation_id}/deliveries` | Read the router's record for each character turn — the `intent`, the `decision` (route, reason, the presence it saw), the `outcome` if a sink reported one, and the canonical `conversation_item` — in intent order. Added in `0.3.0` for World Viewer. |
| `GET /world/v1/facts` | Read current facts, optionally filtered by `subject_id`. |
| `GET /world/v1/timers` | Read timers, optionally filtered by `status`. |
| `GET /world/v1/snapshot` | Read the latest sequence plus bounded current facts and timers. |
| `GET /world/v1/stream` | Receive an initial snapshot or resumed history followed by ordered live deltas over SSE. |

History uses `after_sequence`; conversation, delivery, fact, and timer pages use
`after_item_id`, `after_response_id`, `after_fact_id`, and `after_timer_id`.
Every list accepts `limit`, defaults to 100, and permits at most 500 results. Page responses state
whether more results exist and provide the cursor for the next request. A snapshot marks facts or
timers as truncated rather than implying that a bounded result is complete.

Logins are the world's first character presence: `character.logged_in` / `character.logged_out`
world events are emitted (source `world:character-sessions`, subjects the character and the
region), and once any mind holds a character, `/stage` and `/performances` for that character
must carry its `session_id` or they are refused with 409 `logged_in_elsewhere` — the world
never lets two processes be Beaky. A character nobody is logged in as may still be spoken for
by hand.

A character turn is never authored by Creature World; an agent proposes a provider-neutral
`CharacterUtteranceIntent` and the world decides the stage. Presence is `unknown` with zero
confidence unless the world is configured to assume otherwise (see *Assumed presence*), so
without an assumption every turn takes the private Communicator route with reason
`presence_uncertain`. A mind that wants to speak *while* it thinks asks `/stage` first and
performs the turn itself (see the [Creature Agent manual](creature-agent-manual.md)); a turn
posted to `/responses` after a stage decision is routed exactly as that decision said. The
canonical `ConversationItem` is written before any delivery sink runs and is then offered to every
live conversation subscriber regardless of route, so a turn later performed aloud still appears in
Communicator history. The response body is `{ "disposition", "outcome", "conversation_item" }`
(`Fixtures/CreatureWorld/character-delivery-result-v1.json`). If physical speech is ever chosen
before the Creature Server sink exists, the outcome is recorded as `failed` with
`error_code: physical_speech_not_connected` rather than lost.

Beaky Communicator writes a typed utterance to its local SwiftData outbox before attempting the
POST. Retries reuse the same utterance ID, so an interrupted request cannot make Beaky hear April
twice. A successful response replaces the provisional local item with Creature World's canonical
item, and history synchronization pages forward from the durable API. Creature World records
April's turn in the ordered world-event pipeline as a `conversation.person_utterance` event whose
payload is the `PersonUtterancePercept` (the utterance plus the newest 100 prior conversation
items — a window, not the whole history — addressed to the character); it does not fabricate a
Beaky response. `creature-agent` in world
mode consumes that event from `/world/v1/stream`, thinks with the local model, and posts Beaky's
turn to `…/responses` — see the [Creature Agent manual](creature-agent-manual.md).

The communicator partitions its SwiftData conversation cache and durable outbox by the canonical
configured Creature World URI. Development, staging, and production history must never be merged,
and an offline utterance queued for one World must never be submitted to another. Rows created by
older communicator builds without a server URI remain quarantined and are not assigned to an
environment by guesswork; the selected server refills its cache from canonical history.

Connect to `/world/v1/stream` without a cursor to receive a snapshot before live deltas. Reconnect
with the standard SSE `Last-Event-ID` header, or `after_sequence`, to receive durable history after
that sequence before live delivery. Subscribe-before-query ordering prevents a history/live race.
A slow subscriber is disconnected with `resnapshot_required`; reconnect without a cursor rather
than continuing from a potentially incomplete view.

Requests are bounded to a 1 MiB body, 100 events per batch, 64 concurrent application operations,
and a 10-second application deadline. Saturation returns `overloaded`, lag returns an explicit
resnapshot event, and unavailable persistence returns HTTP 503. Batch acceptance is sequential,
not transactional; retrying a partially completed batch is safe because event identity makes
acceptance idempotent.

Example loopback ingestion:

```bash
curl --fail-with-body \
  -H 'Content-Type: application/json' \
  --data @event.json \
  http://127.0.0.1:8001/world/v1/events

curl --fail-with-body 'http://127.0.0.1:8001/world/v1/events?after_sequence=0&limit=100'
curl --no-buffer http://127.0.0.1:8001/world/v1/stream
```

## Running in production

### Network exposure

Creature World binds to loopback by default. Set `host` or `SERVER_HOSTNAME` deliberately when a
reverse proxy, container network, or another host must reach it. Creature World's HTTP API is open
and does not authenticate callers, including when bound beyond loopback. Restrict access with the
host firewall and trusted network or reverse-proxy boundary. Use TLS at that boundary; the service
does not terminate TLS itself.

Browser access to the SSE endpoint additionally requires the request's exact `Origin` in
`allowed_origins`. Requests without `Origin`, including native applications, are allowed. Creature
World does not emit permissive cross-origin headers.

Do not expose MongoDB publicly. Use authentication, encrypted connections, and a least-privilege
database user for non-development deployments. Keep credentials out of the checked-in JSON and
`/etc/default/creature-world`; use the host's secret-management facility.

### Debian package

Creature World has an independent package because this repository is a monorepo, not a monolithic
application. Build a release binary for direct testing with:

```bash
./build_world.sh
```

On Linux, `./build_world.sh --static` statically links the Swift standard library. The resulting
binary is copied atomically to `world/creature-world`.

Build the Debian binary packages for both architectures on any machine with Docker — the same
Trixie environment, toolchain, and `dpkg-buildpackage` invocation CI uses — with:

```bash
./build_debs.sh                 # amd64 and arm64, packages land in artifacts/
./build_debs.sh --arch amd64    # fuzzball and production are amd64
```

(`./build_deb.sh` is the raw `dpkg-buildpackage` wrapper for a Linux host that already has the
toolchain.) The shared Debian source build produces each monorepo product as a separate binary
package; the Creature World artifact is `creature-world_<version>_<architecture>.deb`. Install
only that package with:

```bash
sudo apt install ./creature-world_0.6.2_amd64.deb
```

The package installs:

- `/bin/creature-world`;
- `/etc/creature/world.json`;
- `/etc/default/creature-world`;
- `/usr/lib/systemd/system/creature-world.service`;
- shell completions for bash, zsh, and fish.

The package does not automatically start the service. Review the configuration, then enable it:

```bash
sudo systemctl enable --now creature-world
systemctl status creature-world
journalctl -u creature-world -f
```

The unit runs with a dynamic user, restarts on process failure, and applies systemd hardening. A
MongoDB outage does not cause a process failure, so systemd leaves the degraded service running
while its internal retry loop reconnects.

**Upgrading restarts an enabled service** (`0.8.0`; #144 — `0.6.1`'s check for an *active*
unit never fired, because `--no-start` stops the unit in `preinst` first): the package's `postinst` calls
`deb-systemd-invoke restart creature-world` when a previous version was installed and the unit
is active, so the new build answers as soon as `apt install` returns. A fresh install still does
not start the service — review `/etc/creature/world.json` first, then `sudo systemctl enable
--now creature-world`. Confirm an upgrade with:

```bash
curl --fail-with-body http://127.0.0.1:8001/world/v1/health   # confirm build_version
```

Graceful shutdown is fast: SIGTERM closes open subscriptions and streams, and the process exits
in well under a second even with clients attached. A contested timer during startup recovery no
longer aborts the MongoDB connect (fixed in `0.2.1`, #138).

## Observability and troubleshooting

Creature World always writes structured logs to standard error, which systemd captures in the
journal. It exports logs, traces, and metrics over OTLP only when
`OTEL_EXPORTER_OTLP_ENDPOINT` is set. The OTLP exporter is not part of the readiness decision, so
a Honeycomb outage does not stop the service or make `/world/v1/health` unavailable.

### Honeycomb

For an interactive development run against Honeycomb's US instance:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=https://api.honeycomb.io
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_HEADERS='x-honeycomb-team=YOUR_API_KEY'
world/creature-world
```

Use `https://api.eu1.honeycomb.io` instead for Honeycomb's EU instance. Creature World supplies
the service name `creature-world`; `OTEL_SERVICE_NAME` may override it when an intentionally
different name is required. Honeycomb Classic also requires a dataset header:

```bash
export OTEL_EXPORTER_OTLP_HEADERS='x-honeycomb-team=YOUR_API_KEY,x-honeycomb-dataset=YOUR_DATASET'
```

The packaged systemd unit reads `/etc/default/creature-world`, but that package-owned file is for
non-secret overrides. Keep the API key in a separate root-readable environment file managed by
the host's secret-provisioning system:

```bash
sudo install -o root -g root -m 0600 /dev/null /etc/creature/world-otel.env
sudoedit /etc/creature/world-otel.env
```

Put the three `OTEL_` assignments from the development example in that file without `export`,
then add a systemd drop-in:

```bash
sudo systemctl edit creature-world
```

```ini
[Service]
EnvironmentFile=/etc/creature/world-otel.env
```

Apply the change and verify both local operation and telemetry delivery:

```bash
sudo systemctl daemon-reload
sudo systemctl restart creature-world
systemctl status creature-world
journalctl -u creature-world --since "5 minutes ago"
```

Then query Honeycomb for `service.name = creature-world`. The shared HTTPS endpoint is a base URL;
the OpenTelemetry HTTP exporter appends the signal paths for traces, metrics, and logs. Never put
the API key in `world.json`, a command-line option, source control, or diagnostic output. See
[Honeycomb's OpenTelemetry configuration guide](https://docs.honeycomb.io/send-data/opentelemetry/)
for endpoint and header details.

Startup logs identify:

- the Creature World build and schema versions;
- the source of each configuration value;
- the MongoDB targets, database, and TLS state without printing credentials;
- connection and schema preparation attempts;
- the HTTP listen address;
- MongoDB loss and recovery;
- graceful shutdown.

Common checks:

```bash
# Is the process serving HTTP?
curl -i http://127.0.0.1:8001/world/v1/health

# Is the development MongoDB process reachable?
docker compose -f compose.creature-world.json exec mongodb \
  mongosh --quiet --eval 'db.adminCommand({ ping: 1 })'

# Is the development replica set writable?
docker compose -f compose.creature-world.json exec mongodb \
  mongosh --quiet --eval 'db.hello().isWritablePrimary'

# What did the packaged service log?
journalctl -u creature-world --since today
```

If health remains unavailable after MongoDB returns, verify:

1. The URI selects `creature_world`.
2. Every replica-set host in the URI or server response is resolvable from the Creature World host.
3. The replica-set name matches the deployment.
4. Authentication and TLS options are correct.
5. The database user can create indexes, read migrations, and read and write the world collections.
6. Connection or migration failures appear in the Creature World logs.

## Testing the persistence contract

Start the development replica set, then run:

```bash
cd Common
MONGODB_TEST_URI='mongodb://127.0.0.1:27017/creature_world?replicaSet=creature-world&directConnection=true' \
  swift test --filter MongoWorldPersistenceTests
```

The integration suite verifies migrations and indexes, both forms of event deduplication,
concurrent unique sequencing, idempotent fact upserts, fact survival across a reconnect, timers,
source checkpoints, durable ordered conversation ingestion, and API persistence across a complete
application restart. The focused in-process HTTP suite also proves ordered and duplicate event and utterance
acceptance, retry safety across changing transport traces, bounded inputs, non-loopback access,
trace validation, overload, deadlines, SSE origin enforcement, and gap-free reconnect behavior.
The tests write uniquely identified records to the `creature_world` database and do not drop the
database afterward. Use a disposable development or CI deployment, never production.

### Black-box service test

`CreatureWorldBlackBoxTests` launches the **built `creature-world` executable** as a child process
and drives it over real TCP the way an adapter or World Viewer would: snapshot on a fresh stream,
`202` acceptance and its live `delta`, history by sequence, `200 duplicate_event`, reconnect with
`Last-Event-ID` replaying exactly the missed event and then continuing live, **SIGTERM and
relaunch on the same port**, and history intact afterwards. It is enabled by the same
`MONGODB_TEST_URI` and runs in well under a second:

```bash
cd Common
MONGODB_TEST_URI='mongodb://127.0.0.1:27017/creature_world?replicaSet=creature-world&directConnection=true' \
  swift test --filter CreatureWorldBlackBoxTests
```

It finds the executable at `.build/debug/creature-world`; set `CREATURE_WORLD_EXECUTABLE` when
building with `--scratch-path` or a release configuration. To run it on Linux exactly as CI does:

```bash
docker run --rm -v "$PWD/Common:/src" -w /src \
  --add-host=host.docker.internal:host-gateway \
  -e 'MONGODB_TEST_URI=mongodb://host.docker.internal:27017/creature_world?replicaSet=creature-world&directConnection=true' \
  swift:6.3.3 swift test
```

CI's Linux job runs the whole Linux-capable package suite this way on every push — contract
fixtures, the HTTP API, the Communicator gateway, persistence, and the black-box service test —
not only the persistence filter.

The normal package suite is:

```bash
cd Common
swift test
```

On Linux, the package manifest omits `PlaylistRuntime` because that client-side library uses
Apple's Combine framework. This keeps Creature World's Swift 6.3.3 Linux build and MongoDB tests
independent from Apple-only application code.

## Decision record

These decisions were established during VW-001 through VW-003 and should be revisited explicitly,
not changed incidentally:

| Decision | Rationale |
| --- | --- |
| Swift 6.3.3 and strict concurrency | Creature World is a Swift service in the existing monorepo and uses modern concurrency guarantees. |
| Hummingbird 2.26.0 | Lightweight, concurrency-native HTTP service aligned with Creature World's workload. |
| JSON configuration | Matches the rest of the Creature software and avoids introducing a second configuration format. |
| MongoDB 8.3.8 replica set | Pins development and CI to the selected MongoDB 8.3 line and supports production-shaped write semantics. |
| Dedicated `creature_world` database | Preserves service ownership and prevents coupling to Creature Server's `creature_server` data. |
| MongoDB gates readiness, not process startup | The service remains observable and recovers automatically through database outages. |
| HTTP 503 for unavailable persistence | Load balancers and operators receive an honest readiness signal. |
| Versioned JSON plus SSE boundary | Gives native clients a small durable request/response API and an ordered live feed without coupling handlers to MongoDB. |
| Open HTTP API | Keeps trusted-LAN clients simple; firewall and ingress policy own network access control. |
| Exact browser Origin allowlist | Prevents an arbitrary website from opening an authenticated live stream. |
| Independent Debian package and version | The repository is a monorepo whose deployable products have separate lifecycles. |
| One authoritative `World` actor | Preserves deterministic ordering while concurrent tasks keep persistence I/O outside the actor. |
| Bounded ingress, derivation, and subscription queues | Prevents resource exhaustion and makes overload or resnapshot requirements explicit. |
| Durable processed marker separate from acceptance | Makes failures after append retryable without reducing completed duplicates again. |
| Privacy-safe event spans and metrics from the first actor slice | Keeps causal telemetry connected without copying private event payloads into Honeycomb. |
| Shared periodic health-check lifecycle | Keeps cadence, graceful cancellation, and cleanup consistent while each service owns its protocol-specific health probe. |

Update this manual whenever an implementation change affects configuration, operational behavior,
persistence guarantees, packaging, or recovery semantics.
