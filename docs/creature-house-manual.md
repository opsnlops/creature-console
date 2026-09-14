# Creature House Manual

`creature-house` is the Home Assistant adapter for Beaky's Virtual World: a small Linux service
that follows Home Assistant's event stream and tells Creature World what the house sees —
doors, motion, people, the temperature, what the cameras noticed — and, the other way, sets
lighting scenes when someone asks a bird to. Source vocabulary (entity IDs, `on`/`off`,
`not_home`) stops here; the world hears about places and people.

```text
Home Assistant (10.3.2.5:8123)
    ── WebSocket state_changed ──▶ creature-house ── POST /world/v1/events ──▶ Creature World
    ◀── scene.turn_on ─────────── creature-house ◀── /world/v1/stream (house.scene_requested) ──
```

## Configuration

`/etc/creature/house.json`:

```json
{
  "home_assistant": { "url": "http://10.3.2.5:8123" },
  "world_url": "http://127.0.0.1:8001/world/v1",
  "house_id": "house:aprils-nest",
  "scenes": { "offer": true },
  "mappings": [
    { "entity_id": "lock.front_door", "subject_id": "place:front-door", "kind": "lock" },
    { "entity_id": "binary_sensor.entryway_motion", "subject_id": "place:entryway", "kind": "motion" },
    { "entity_id": "person.april", "subject_id": "person:april", "kind": "person" },
    { "entity_id": "sensor.outside_temperature", "subject_id": "place:outside",
      "kind": "measurement", "predicate": "temperature_f", "minimum_change": 1.0 },
    { "entity_id": "binary_sensor.front_door_person_detected", "subject_id": "place:front-door",
      "kind": "detection", "detects": "person" }
  ]
}
```

The token is **never** in this file: put a long-lived access token (Home Assistant → your
profile → Security) in `/etc/default/creature-house` as `HA_TOKEN=…` and keep that file
`chmod 600`. The service refuses to start without it.

| Kind | Entity | State change → world event |
| --- | --- | --- |
| `lock` | `lock.*` | `locked` → `door.locked`; `unlocked` → `door.unlocked` (April's doors report through the lock, not a contact sensor) |
| `door` | `binary_sensor.*` (door class) | `on` → `door.opened`; `off` → `door.closed` |
| `motion` | `binary_sensor.*` (motion) | `on` → `motion.detected`; `off` → `motion.cleared` |
| `person` | `person.*` / `device_tracker.*` | `home` → `person.arrived`; anything else → `person.left` (moving between two away zones is neither) |
| `measurement` | `sensor.*` with a number | → `environment.measurement_changed` with `predicate` and `value`; a move smaller than `minimum_change` **from the last value the world was told** is dropped (so a thermometer creeping 0.2° at a time still gets announced once it has drifted a degree; `0.1.1`) |
| `detection` | `binary_sensor.<camera>_person_detected` etc. | `on` → `camera.person_seen` / `vehicle_seen` / `animal_seen` (`detects`); `off` is not news, and a camera already seeing something at startup is not news either. At startup the adapter also announces `camera.watching` for each such place (`0.1.2`), so a camera that has seen nothing is a fact the birds can state — "The cameras at the front door and the driveway have seen nobody and nothing in the last ten minutes" — rather than a shrug |

The packaged `house.json` maps April's weather station and power monitor as measurements —
`humidity_percent`, `wind_mph`, `rain_today_in`, `pressure_hpa`, `pm25_ugm3` on `place:outside`
and `power_w` on the house — and the agent has words for each ("It is windy outside: about 18
miles per hour", "It has not rained today", "The air outside is clean", "The house is drawing
about 2.2 kilowatts right now"). New predicates are just a mapping line plus a phrasing.

Every event is about the mapping's `subject_id` (a `place:` or `person:`), `observed` with
confidence 1, `occurred_at` = Home Assistant's `last_changed`, `source` =
`home-assistant:<entity>`, and `source_event_id` = Home Assistant's context id — so a change
delivered twice (a reconnect, a replayed outbox) is one event. `unknown` / `unavailable` states
are ignored.

**Startup snapshot.** Every mapped entity's current state is announced once (keyed
`snapshot:<last_changed>:<state>`, so a restart does not repeat it); then the live stream is
followed, reconnecting every 5 s when it drops. **Outbox:** events the world cannot take
(down, restarting) wait in `/var/lib/creature-house/outbox.jsonl` in order and follow within
30 s of it returning — a door opening during a World deploy is not lost.

## What the world does with it (World `0.8.0`)

`HouseReducer` turns the events into facts on the place or person: `door.lock`,
`door.state`, `motion.active` (true for ten minutes), `seen.person` / `seen.vehicle` /
`seen.animal` (ten minutes), `presence.state` (**observed** — this supersedes the configured
assumption, and the delivery router reads it first: the router stops assuming),
`environment.<predicate>`. List the region's places in `world.json` so the minds in it are
told about them:

```json
"regions": { "region:home": { "stage_id": "…", "places": ["house:aprils-nest", "place:outside", "place:front-door", "place:entryway"] } }
```

The birds then hear, in "What you know": "The front door was unlocked just now.", "A vehicle
was seen at the driveway 3 minutes ago.", "It is 68 degrees outside.", "April is home."

## Scenes: "Beaky, set the lights to normal evening"

With `scenes.offer` on, the adapter posts `house.scenes_offered` at startup (the friendly names
of every `scene.*`), which becomes the `house.scenes` fact on `house_id`, phrased to the minds
as "You can set the lights to: Normal Evening, Movie Time, …". Recognising an ask is a
**world rule, not a model roll**: at ingress, `SceneRequestRule` matches the words against the
offered names (case- and punctuation-insensitive, longest name wins). A message that is
*nothing but* a scene's name — "@beaky normal evening", "Goodnight, please" — is an ask; a
name inside a longer sentence needs a trigger word (set, switch, turn, make, lights, scene,
mode, go) so "I love movie time" is a mention, not an ask (`0.8.1`). The minds are told they
cannot set scenes themselves and must not claim the lights are changing unless the world says
the house is doing it (agent `2.62.2`). A match posts `house.scene_requested`; the adapter, following the
world's stream, calls `scene.turn_on` and posts `house.scene_activated` → the `house.scene`
fact. The mind that was asked is told "April just asked for the lights to be set to Normal
Evening, and the house is doing it right now" in the same percept, so it answers in its own
voice rather than narrating a tool call. All of it is in the Viewer's Timeline: the words →
`house.scene_requested` → `house.scene_activated` → the fact.

## Running it

```bash
sudo apt install ./creature-house_<version>_amd64.deb
sudo vim /etc/default/creature-house        # HA_TOKEN=...
sudo vim /etc/creature/house.json           # mappings
sudo systemctl enable --now creature-house
journalctl -u creature-house -f
```

The log's `Snapshot of the house` line lists how many entities were read; each change logs
`The house says` with the entity, its state, and the world event type. Upgrades restart an
enabled unit. Observability is the shared OpenTelemetry bootstrap (`creature-house` service
name); `creature_house.events` counts what the house said.

For development, run it on a laptop against the real house and a local World:

```bash
HA_TOKEN=... swift run creature-house --config house.json --log-level info
```

## Tests

`CreatureHouseTests`: the translator (every kind, idempotent snapshot keys, dead states,
minimum change, detections only on `on`), configuration (refusals with reasons), the
WebSocket handshake and a live change against a stub Home Assistant (plus a refused token),
REST snapshot / scene list / `scene.turn_on`, and delivery with the world away (the outbox
survives a restart and drains in order). World side: `HouseReducerTests`, `HouseCommandTests`
(the rule and the ingress hook), and `HousePresenceTests` (evidence over assumption; an ask
becomes a request event and the fact the mind is told).
