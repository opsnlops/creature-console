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

The service currently exposes `GET /v1/health`. Its persistence repositories and schema establish
the foundation for later ingestion, query, simulation, and viewer APIs.

## Quick start for development

The repository pins MongoDB 8.3.8 and configures it as a single-node replica set:

```bash
docker compose -f compose.creature-world.json up -d
cd Common
swift run creature-world
```

The Compose project persists MongoDB data in its `mongodb-data` volume and initializes a replica
set named `creature-world`. The default service address is `http://127.0.0.1:8000`.

Check readiness with:

```bash
curl --fail-with-body http://127.0.0.1:8000/v1/health
```

A ready response is HTTP 200:

```json
{
  "status": "ok",
  "schema_version": 1,
  "build_version": "0.1.1",
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
| HTTP port | `port` | `SERVER_PORT` | `--port`, `-p` | `8000` |
| MongoDB URI | `mongodb_uri` | `MONGODB_URI` | `--mongodb-uri` | Local replica set |

Example:

```json
{
  "host": "127.0.0.1",
  "mongodb_uri": "mongodb://127.0.0.1:27017/creature_world?replicaSet=creature-world&directConnection=true&connectTimeoutMS=5000",
  "port": 8000
}
```

`--log-level` controls log verbosity and defaults to `debug`. Supported values are `trace`,
`debug`, `info`, `notice`, `warning`, `error`, and `critical`.

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

`GET /v1/health` is a readiness check:

- HTTP 200 with `status: "ok"` and `mongodb: "ok"` means the required schema record is readable.
- HTTP 503 with `status: "unavailable"` and `mongodb: "unavailable"` means callers must not send
  work that depends on persistence.

An HTTP 503 does not mean the process should be restarted. Supervisors should use process exit for
liveness and `/v1/health` for readiness. This distinction allows Creature World to survive a
MongoDB restart or temporary network outage and recover in place.

Example unavailable response:

```json
{
  "status": "unavailable",
  "schema_version": 1,
  "build_version": "0.1.1",
  "service": "creature-world",
  "mongodb": "unavailable"
}
```

### Collections and indexes

Schema migration 1 creates the following collections and indexes:

| Collection | Purpose | Important indexes |
| --- | --- | --- |
| `world_events` | Immutable accepted world events | Unique `event_id`; unique `world_sequence`; unique source ID plus source event ID when present; event type/time; subject IDs |
| `world_counters` | Atomic sequence allocation | `_id: "world_sequence"` counter document |
| `facts` | Durable facts and current-state reads | Unique `fact_id`; active facts by subject, predicate, validity, and supersession |
| `timers` | Durable simulator timers | Unique `timer_id`; pending timers by status and due time |
| `source_checkpoints` | Per-source cursor or checkpoint state | Unique `source_id` |
| `schema_migrations` | Applied Creature World schema versions | Migration version in `_id` |

The migrator is idempotent and runs whenever a connection is established. Writes use majority write
concern.

Event ingestion is idempotent in two ways:

- Reusing an `event_id` returns the event already accepted.
- Reusing a source ID and source event ID returns the event already accepted.

`world_sequence` is allocated atomically and is unique and increasing. It is not promised to be
gap-free: a sequence may be allocated before an insert loses a deduplication race or fails.
Consumers must order by the value, not infer missing events from a gap.

Current facts are records where both `valid_to` and `superseded_by` are null. They are stored in
MongoDB, so reconnecting or restarting Creature World does not erase the current world state.

## Running in production

### Network exposure

Creature World binds to loopback by default. Set `host` or `SERVER_HOSTNAME` deliberately when a
reverse proxy, container network, or another host must reach it. Binding to a non-loopback address
does not add authentication or TLS; provide those controls at the appropriate network boundary.

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

Build the Debian binary packages from the repository root with:

```bash
./build_deb.sh
```

The shared Debian source build produces each monorepo product as a separate binary package. The
Creature World artifact is written beside the repository as
`creature-world_<version>_<architecture>.deb`. Install only that package with:

```bash
sudo apt install ./creature-world_0.1.1_amd64.deb
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

## Observability and troubleshooting

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
curl -i http://127.0.0.1:8000/v1/health

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
concurrent unique sequencing, fact survival across a reconnect, timers, and source checkpoints.
The tests write uniquely identified records to the `creature_world` database and do not drop the
database afterward. Use a disposable development or CI deployment, never production.

The normal package suite is:

```bash
cd Common
swift test
```

On Linux, the package manifest omits `PlaylistRuntime` because that client-side library uses
Apple's Combine framework. This keeps Creature World's Swift 6.3 Linux build and MongoDB tests
independent from Apple-only application code.

## Decision record

These decisions were established during VW-001 through VW-003 and should be revisited explicitly,
not changed incidentally:

| Decision | Rationale |
| --- | --- |
| Swift 6.3 and strict concurrency | Creature World is a Swift service in the existing monorepo and uses modern concurrency guarantees. |
| Hummingbird 2.26.0 | Lightweight, concurrency-native HTTP service aligned with Creature World's workload. |
| JSON configuration | Matches the rest of the Creature software and avoids introducing a second configuration format. |
| MongoDB 8.3.8 replica set | Pins development and CI to the selected MongoDB 8.3 line and supports production-shaped write semantics. |
| Dedicated `creature_world` database | Preserves service ownership and prevents coupling to Creature Server's `creature_server` data. |
| MongoDB gates readiness, not process startup | The service remains observable and recovers automatically through database outages. |
| HTTP 503 for unavailable persistence | Load balancers and operators receive an honest readiness signal. |
| Independent Debian package and version | The repository is a monorepo whose deployable products have separate lifecycles. |

Update this manual whenever an implementation change affects configuration, operational behavior,
persistence guarantees, packaging, or recovery semantics.
