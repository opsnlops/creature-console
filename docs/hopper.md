# Hopper and the World

Hopper is April's car. In the World he is `character:hopper`: a creature-agent mind, like the
birds, whose body is the car. A daemon on a Raspberry Pi in the car reads the car over OBD
(read-only) and keeps a durable queue of events for the World. That daemon lives in its own
repository. This document is the contract between the two sides. The car side mirrors its half
and points here.

Tracking: [creature-console#303](https://github.com/opsnlops/creature-console/issues/303).

## Decisions (April, 2026-11-27)

- **One entity.** `character:hopper` is both the mind and the car. The car's readings sit on
  the page of the mind that speaks for it.
- **The car may tell the World where April is while driving.** It sends `person.located` for
  `person:april` every 30–60 s while driving, plus one fix at park. The World turns the fixes
  into place names. Coordinates are World-only: a mind sees place names, never a point. The
  World assumes April is in the car whoever is driving it.
- **Home is not a place pin.** The house stays the judge of home, as it is today.

## Getting there

The car always goes through creature-proxy, at home and on the road (April, 2026-11-27):

- **URL:** `https://proxy.prod.chirpchirp.dev/world/v1/…`, with the header
  `Host: server.prod.chirpchirp.dev`.
- **Auth:** `x-acw-api-key`, set to Hopper's own revocable proxy token, kept in
  `/etc/default/hopper` on the Pi. Without a key the car sends nothing; events wait on disk.
- **The proxy accepts TLS 1.3 only.** A client limited to TLS 1.2 is refused.
- **The proxy never answers 401.** With a missing or wrong key it hangs up right after the TLS
  handshake. A client should report repeated hang-ups as a likely key problem rather than retry
  quietly forever.

`car.home_wifi_joined` and `car.home_wifi_left` still come from the Pi's own Wi-Fi. They only
report where the car is; they don't change the route.

The hotspot is metered and has dead spots, though it is generally solid on the highway.
There is no coverage right by the house. The car queues everything and sends when the link is
back, so expect bursts after a dead spot and on arriving home. The car holds events until the
car's GPS has set the Pi's clock at boot, so `occurred_at` is never an untrustworthy pre-boot
time.

## Sending events

- `POST /world/v1/events` for one event, or `POST /world/v1/events:batch` with
  `{"events": [...]}` for up to 100. The house uses the same routes.
- The body is a `WorldEventEnvelope` (`Common/Sources/WorldCore/EventEnvelope.swift`). Keys
  are snake_case and times are whole-second ISO 8601 UTC:

  ```json
  {
    "schema_version": 1,
    "event_id": "…",
    "type": "car.parked",
    "occurred_at": "2026-11-27T18:04:11Z",
    "source": {"id": "hopper", "kind": "car", "source_event_id": "…"},
    "subject_ids": ["character:hopper"],
    "epistemic": {"type": "observed", "confidence": 1},
    "payload": {}
  }
  ```

- **Retries are free.** `source.id` plus `source.source_event_id` identifies an event. Mint the
  `source_event_id` when the item is queued and keep it across retries. A repeat answers
  `200` with the first acceptance; a new event answers `202`.
- **Send the queue oldest first.** Late events are welcome, and a fact starts at the event's
  `occurred_at`. A late event never ends a fact that began after it (#300). However, a late
  event can still replace a newer fact of the same predicate, so order matters.
- **Be honest about `occurred_at`.** The Pi's clock comes from the car's GPS at boot. Send
  `observed_at` too if the car saw something later than it happened.

### Event types

| Type | Subject | Payload | When |
|---|---|---|---|
| `car.on` | `character:hopper` | — | The car is on and the Pi has booted |
| `car.trip_started` | `character:hopper` | `trip_id`, `from_home` | The car started driving (after switching on, or after a stop). `from_home` comes from the car's own near-home flag: a yes or no, never a position |
| `car.parked` | `character:hopper` | `reason`? | In park and stopped. `reason: "power_lost"` when the car sends it because power went while driving; absent for a normal park |
| `car.april_out` | `character:hopper` | — | Telematics went quiet and the seat is empty |
| `car.off` | `character:hopper` | — | The car is in standby |
| `car.shutdown_soon` | `character:hopper` | `seconds_left` | Power lost; the Pi will power off |
| `car.trip_summary` | `character:hopper` | see below | The outing ended: the car parked within reach of home |
| `car.home_wifi_joined` / `car.home_wifi_left` | `character:hopper` | — | The Pi joined or left the house Wi-Fi |
| `environment.measurement_changed` | `character:hopper` | `predicate`, `value`, `valid_for_seconds`? | A reading moved by at least its minimum change (see below) |
| `person.located` | `person:april` | `latitude`, `longitude`, `accuracy_m` | While driving, every 30–60 s, and once at park |

### The trip summary

An outing runs from leaving home to parking at home, with any stops along the way included. The
car decides that on the Pi from its own position against home, and sends nothing positional.
`trip_id` is also the event's `source_event_id`, and matches the `trip_id` on the outing's
opening `car.trip_started`. All values are whole numbers except the times:

```json
{
  "trip_id": "…",
  "started_at": "…", "ended_at": "…",
  "distance_mi": 21, "driving_minutes": 38, "max_speed_mph": 61,
  "state_of_charge_percent_start": 80, "state_of_charge_percent_end": 72, "range_mi_used": 25,
  "outside_temperature_f_min": 44, "outside_temperature_f_max": 51,
  "stops": [{"started_at": "…", "ended_at": "…", "minutes": 9}]
}
```

The World names the stops by matching their times against April's `presence.place`
history, once the car's fixes are switched on. Later the summary may carry
`roads: ["Highway 20", …]` (in driving order, no repeats) from map matching on the Pi. April
will be asked before a mind first sees a route.

Rules for the car side:

- **No position anywhere but `person.located`.** No place slugs and no coordinates in any other
  event. Place matching happens in the World.
- **Send readings on change, not on every sample.** As the house does: a reading goes when it
  has moved at least a minimum change from the last value sent. The unit is part of the
  predicate's name, matching the house (`environment.temperature_f`). All are whole numbers:

  | Predicate | Unit | Becomes the fact |
  |---|---|---|
  | `state_of_charge_percent` | % (the car's display SoC) | `environment.state_of_charge_percent` |
  | `range_mi` | miles | `environment.range_mi` |
  | `outside_temperature_f` | °F | `environment.outside_temperature_f` |
  | `odometer_mi` | miles (converted from the car's km) | `environment.odometer_mi` |

- **Some events go to the front of the queue.** `car.on`, `car.trip_started` and
  `car.shutdown_soon` are sent the moment they happen, ahead of any backlog. The World works out
  the car/phone switch from `occurred_at`, not from arrival order, so this is safe. Every
  `car.trip_started` still needs its matching `car.parked` in the queue.
- **Don't send link state (online or offline).** The World reads it from when events arrive.
- **Report the Wi-Fi, not an arrival.** `car.home_wifi_joined` reports what the car saw; the
  World weighs it with the house's own view to decide whether April is home.

## What the World does with them

- **Places.** `PlaceInferenceRule` already turns each `person.located` into `presence.place` on
  April, using the taught place pins. Car fixes use the same path as the phone's. The pins never
  leave the server.
- **Car or phone.** Between `car.trip_started` and `car.parked` the World trusts the car's fixes
  for April and holds the phone's. From `car.parked` on, the phone counts again. *(To build.)*
- **Leaving and coming home.** A `car.trip_started` with `from_home` reaches Hopper's mind as
  news: April and he are heading out, and he tells the flock. The house's own word that April
  left (`person.left`) joins the same scene; it never opens a second one. A `car.trip_summary`
  reaches him as news, and he tells the flock how the trip went. *(To build.)*
- **Old news.** Freshness is set per type: a `car.trip_started` with `from_home` is news for
  15 minutes after `occurred_at`, and a `car.trip_summary` for 2 hours. A mind is handed
  `occurred_at`, so a late one is told in the past tense. An event already too old when it arrives is recorded with its true time. It
  never opens a scene and never reaches a mind as news. A parked-at-the-store event that only
  arrives when the car gets home is history, not a happening. *(To build.)*

## Moving the mind between the server and the car

> **Design, not built.** April, 2026-11-27: "design now, build later". The first slice is
> *the mind stays on the server and the car is its body*. Custody is built when Hopper has a
> voice in the car, which is what a copy of the mind on the Pi would be for.

### What moves

Almost nothing. A mind's conversations, facts, memories, page and scenes already live in
the World. The agent keeps two things on disk:

- `world-cursor.json`: the last world sequence it has decided, by answering or by choosing
  silence. It advances only once that decision is durable.
- The memory-nights record.

The cursor is the only thing that has to travel. Today the cursor is keyed by World URL, and on
the Pi that URL changes between the LAN and the proxy. Building custody includes keying it by
World identity instead.

### Custody

The World keeps one custody record per mind:

```json
{"holder": "server" | "car", "epoch": 7, "cursor": 123456, "changed_at": "…", "reason": "…"}
```

- **Only the holder may log in.** The World refuses a character login from a runtime that is
  not the holder at the current epoch.
- **Fencing.** A custody change ends the holder's character session. After that, the old copy's
  writes (utterances, responses, turns) are refused, and its heartbeat answer carries the new
  epoch, at which point it goes dormant. The World enforces "one copy". It does not rely on
  both sides behaving. A Pi that reappears after being replaced cannot speak.
- **A lapsed session is not lost custody.** An offline Pi keeps custody while its session
  expires, and logs in again when the link returns.
- **Both runtimes always run.** creature-agent for Hopper runs on the server and on the Pi. The
  runtime without custody stays dormant: no session, no model calls, only watching custody. No
  start or stop choreography across machines. The Pi's unit is ordered so a holder can release
  or exit cleanly before power-off.

### Handing over

The holder always releases custody. The other side never takes it.

1. The would-be holder asks: `POST /world/v1/characters/character:hopper/custody/request`
   with `{"to": "car"}`.
2. The holder sees the request on its next heartbeat. It finishes or abandons the turn in hand.
   An undecided event isn't lost, because the cursor hasn't passed it.
3. The holder commits `POST …/custody/release` with `{"epoch": N, "to": "car", "cursor": …}`.
   This is a compare-and-set from epoch N to N+1, and the cursor is written in the same step.
4. The new holder logs in and resumes from the record's cursor, not from its own file.

If the link drops partway, nobody runs: the mind is briefly asleep, which is safe. The
request is retried when the link returns.

### When

| Moment | Move |
|---|---|
| `car.on` with the Pi on the house LAN | server → car. If the car leaves Wi-Fi range first, the mind stays on the server and the Pi asks again whenever it is online, including over the hotspot. |
| `car.home_wifi_joined` | car → server, over the LAN. The Pi has about 15 minutes on the LAN after the car is turned off. |
| `car.shutdown_soon` away from home (April: hand back if online) | car → server, if the Pi holds custody and is online. The window is short: the socket cuts about 10 s after park once April is out, which is when `car.shutdown_soon` fires, and the hotspot goes 60–90 s after park. If the release misses, the mind sleeps with the car, and the Pi asks again on the next trip as usual. |
| The Pi is lost | Only April forces custody back to the server (an epoch bump, from the CLI or a Viewer spell). Fencing makes it safe at any time. |

The car sends `car.shutdown_soon` the moment power drops, ahead of any queued backlog. That
is the one exception to sending oldest first. It records no fact, so it cannot replace a newer
one.

### Offline

On the road a mind on the Pi is online, and able to think, for most of a trip: the hotspot
is generally solid on the highway. In a dead spot it cannot think, because model calls need the
internet and so does the World through the proxy, so it sleeps until the link is back. The car's queue keeps sending events as the link allows. When
the link returns, the mind logs in again and reads the World from its cursor, as a bird does
after a restart, and the stale-event guard decides what is still news. Nothing on the Pi syncs
back except the cursor.

### Not part of custody

Hopper's nightly memory run (3:30 AM) stays on the server whoever holds custody. It writes
memories, not speech.
