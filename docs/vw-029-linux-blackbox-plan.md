# VW-029 Completion — Black-Box Linux Service Test and Linux CI

**Issue:** [#124](https://github.com/opsnlops/creature-console/issues/124) (reopened 2026-09-10)
**Roadmap:** Phase 1, Creature World
**Product:** Creature World (test and CI only; no runtime change expected)

## Why this matters for the magic

Everything downstream — Beaky's turns (#134), the agent's percept stream (#105), World Viewer —
leans on `/world/v1/stream` reconnect semantics and on the service surviving a restart. Today the
only proof those work on the Linux box that actually runs Beaky's world is a manual run from
2026-09-09. A stage that might quietly drop a turn on reconnect is not a stage we can trust her
to.

## What is already covered (and how)

| Done-when clause | Evidence | Gap |
| --- | --- | --- |
| Live delta, read by sequence, duplicate idempotent, reconnect without gap | `WorldHTTPAPITests` in-process `.test(.router)` with fake services | Not the real process, not TCP, not Linux |
| Event survives restart | `MongoWorldPersistenceTests` rebuilds the application object in one process | Not an OS process restart |
| Malformed / oversized / overloaded / lagging fail explicitly | `WorldHTTPAPITests` | none |
| Contract tests pass on Swift 6.3.3 Linux | `tests.yml` runs only `--filter MongoWorldPersistenceTests` in the container | everything else is macOS-only |

## Design

### 1. `CreatureWorldBlackBoxTests` (Swift Testing, `Common/Tests/CreatureWorldTests/`)

Enabled only when `MONGODB_TEST_URI` is set, like the persistence suite. Drives the **built
`creature-world` executable** as a child `Process` over real TCP:

```text
locate .build/<config>/creature-world next to the test bundle
pick a free loopback port
launch: creature-world --host 127.0.0.1 --port N --mongodb-uri $MONGODB_TEST_URI
wait for GET /world/v1/health == 200 and mongodb == "ok"
open  GET /world/v1/stream                      -> `snapshot` (latest_sequence L)
POST  /world/v1/events  (fresh event_id)        -> 202 accepted, world_sequence S > L
stream receives `delta` id S
GET   /world/v1/events?after_sequence=S-1       -> the event, has_more false
POST  same event again                          -> 200 duplicate_event, same world_sequence
close stream
POST  second event                              -> 202, S+1
open  GET /world/v1/stream  Last-Event-ID: S    -> `event` id S+1 (history, no gap, no snapshot)
POST  third event                               -> 202, S+2 ; stream receives `delta` id S+2
SIGTERM the process; wait for exit 0 (graceful shutdown closes streams)
relaunch on the same port; wait for health
GET   /world/v1/events?after_sequence=S-1       -> exactly the three events, in order
GET   /world/v1/stream  Last-Event-ID: S+2      -> no history, then `delta` for a fourth event
```

HTTP is AsyncHTTPClient (already a package dependency; streams SSE bodies on Linux where
`URLSession.bytes` does not exist). SSE frames are parsed with a tiny `\n\n`-delimited reader in
the test; no production code changes.

Uses a unique `source.id` per run so repeated runs against the shared dev database stay
independent; asserts only on sequences it observed, never on absolute counts.

### 2. Linux CI runs the Linux-capable suites

`tests.yml`'s container job runs `swift test` for every target that compiles on Linux instead of
one filter. `Package.swift` already removes the Apple-only targets on Linux, so the expected
command is plain `swift test` — confirmed or narrowed by the first full container run in this
branch. The black-box suite runs there too because MongoDB is already started for that job.

### 3. Local parity

`docs/creature-world-manual.md` documents how to run the black-box suite locally against the
Compose MongoDB (`MONGODB_TEST_URI=… swift test --filter CreatureWorldBlackBoxTests`) and in the
`swift:6.3.3` container.

## Non-goals

`/v1/entities`, `/v1/provenance`, `/v1/characters/*` (VW-010/VW-011); any change to route
behaviour. If the black-box test finds a defect, it gets its own issue and fix.

## Exit

`#124`'s two remaining boxes checked: the black-box suite passes locally on macOS and in the
Swift 6.3.3 Linux container against MongoDB 8.3, and `tests.yml` runs it plus the full
Linux-capable suite on every push.
