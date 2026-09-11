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
  "build_version": "0.2.1",
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

Example:

```json
{
  "host": "127.0.0.1",
  "mongodb_uri": "mongodb://127.0.0.1:27017/creature_world?replicaSet=creature-world&directConnection=true&connectTimeoutMS=5000",
  "port": 8001
}
```

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
  "build_version": "0.2.1",
  "service": "creature-world",
  "mongodb": "unavailable"
}
```

### Collections and indexes

Schema migrations 1 through 4 establish the following collections and indexes:

| Collection | Purpose | Important indexes |
| --- | --- | --- |
| `world_events` | Immutable accepted world events | Unique `event_id`; unique `world_sequence`; unique source ID plus source event ID when present; event type/time; subject IDs |
| `world_event_processing` | Durable completion markers for accepted events | Unique event ID in `_id` |
| `world_counters` | Atomic sequence allocation | `_id: "world_sequence"` counter document |
| `facts` | Durable facts and current-state reads | Unique `fact_id`; active facts by subject, predicate, validity, and supersession |
| `timers` | Durable simulator timers | Unique `timer_id`; recoverable timers by status and due time |
| `source_checkpoints` | Per-source cursor or checkpoint state | Unique `source_id` |
| `utterance_ingresses` | Durable, idempotent person-utterance processing records | Unique utterance ID |
| `conversation_items` | Canonical conversation history shared by clients and characters | Unique item ID; conversation/time/item order |
| `character_deliveries` | Durable delivery decision and outcome for each character turn, keyed by `response_id` | Unique `decision.attempt_id`; conversation/time order |
| `schema_migrations` | Applied Creature World schema versions | Migration version in `_id`; current migration is 4 |

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
| `GET /world/v1/facts` | Read current facts, optionally filtered by `subject_id`. |
| `GET /world/v1/timers` | Read timers, optionally filtered by `status`. |
| `GET /world/v1/snapshot` | Read the latest sequence plus bounded current facts and timers. |
| `GET /world/v1/stream` | Receive an initial snapshot or resumed history followed by ordered live deltas over SSE. |

History uses `after_sequence`; conversation, fact, and timer pages use `after_item_id`,
`after_fact_id`, and `after_timer_id`.
Every list accepts `limit`, defaults to 100, and permits at most 500 results. Page responses state
whether more results exist and provide the cursor for the next request. A snapshot marks facts or
timers as truncated rather than implying that a bounded result is complete.

A character turn is never authored by Creature World; an agent proposes a provider-neutral
`CharacterUtteranceIntent` and the world decides the stage. Until a presence source is connected
(Home Assistant adapter, presence reducer) presence is reported as `unknown` with zero confidence,
so every turn takes the private Communicator route with reason `presence_uncertain`. The
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
payload is the `PersonUtterancePercept` (the utterance plus the prior conversation items,
addressed to the character); it does not fabricate a Beaky response. `creature-agent` in world
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
sudo apt install ./creature-world_0.2.1_amd64.deb
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

**Upgrading does not restart the service** (#144). The package is installed with `--no-start`,
which also suppresses the restart-on-upgrade behaviour, so after `apt install` of a newer
`.deb` the previous binary keeps running (or, if the unit was stopped, stays stopped). Until #144
is fixed, always follow an upgrade with:

```bash
sudo systemctl restart creature-world
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
