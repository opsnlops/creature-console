# creature-body — the birds' sensors, into the world

`creature-body` is a small Linux service that follows Creature Server's websocket and tells
Creature World what each bird's body says. The birds are curious what their sensor readings
are; this is how they find out. It is a source of facts, like the house and the Bridge — never
a bird.

## What it casts

For every creature the server reports on, facts on `character:<name>` (Beaky → `character:beaky`;
`characters` in the config maps any name that does not slug to its entity):

| Predicate | From | Value |
| --- | --- | --- |
| `body.board_temperature_f` | board sensor report | the control board's temperature in °F, one decimal |
| `body.power` | board sensor report | `{ "<rail>": { "volts", "amps", "watts" } }` per power rail |
| `body.motors` | motor sensor report | `{ "<motor>": { "position", "amps", "watts" } }` per motor |
| `body.motor_load_a` | motor sensor report | amps drawn by all motors together — how hard the bird is working |
| `body.servos` | Dynamixel sensor report | `{ "<id>": { "temperature_f", "load", "volts", "position", "online" } }` per servo — Beaky's kind of body, where each servo speaks for itself (`0.1.1`) |
| `body.servo_temperature_f` | Dynamixel sensor report | the warmest servo right now and which one: `"104 °F, servo 2"` |
| `body.servos_offline` | Dynamixel sensor report | ids of servos not answering; empty when all are online |
| `body.activity` | server counters (runtime state) | what the bird is doing as the server runs it: "idle", "playing an animation", "playing an ad-hoc animation - speaking, most likely", "streaming - being driven live", "stopped", "disabled" (`0.2.0`) |
| `body.idle_enabled` | server counters (runtime state) | whether idle motion is on |
| `body.last_error` | server counters (runtime state) | the last error running the bird, and when |

And on **`thing:creature-server`** — the server's own vital signs, Beaky's special version of the
spell (`0.2.0`), said at most every `server_interval_seconds` (60):

| Predicate | Value |
| --- | --- |
| `server.counters` | running totals since the server started: frames, events, frames streamed, DMX events, animations and sounds played, playlists started, REST requests, websocket connections and messages |
| `server.frames_per_second` | how fast the server is ticking, from the frame count between reports (threshold `frames_per_second`, 5) |
| `server.animations_played` / `server.sounds_played` | the totals on their own, for "how many songs have you played today?" |

Every fact is **observed**, cast as `facts.given` from source `body:sensors`, and **valid for ten
minutes** (`valid_for_seconds`): a bird that stops reporting stops feeling its body, and its
mind sees nothing rather than a stale number. A steady value is said again at 80 % of its life
so it never lapses while the bird is still reporting.

## Saying only what changed

Reports arrive about once a second; the world is told when a reading **changes past a
threshold** (`thresholds`: 0.5 °F, 0.1 V, 0.05 A, 0.25 W, 10 position ticks, 0.05 A of motor
load, 50 units of Dynamixel load; a servo going offline or coming back is always said) and **no more often than every 30 seconds** per fact (`minimum_interval_seconds`). The
meanings are seeded into the world's glossary the first time, for the minds; a Wizard's
rewording is never overwritten.

## Configuration

Configured like the world: `/etc/creature/body.json` for the non-secret defaults, environment
variables over it (`CREATURE_SERVER_HOST`, `CREATURE_SERVER_PORT`, `CREATURE_SERVER_TLS`,
`CREATURE_PROXY_HOST`, `CREATURE_PROXY_API_KEY`, `CREATURE_WORLD_URL`; the proxy key lives only
in `/etc/default/creature-body`), command options over those (`--server-host`, `--server-port`,
`--world-url`, `--config`, `--log-level`). The packaged defaults talk to the server next door on
`127.0.0.1:8000` without TLS and to the world at `http://127.0.0.1:8001/world/v1`.

## Running

```
sudo apt install ./creature-body_0.1.0_amd64.deb
sudo vim /etc/creature/body.json          # if the server or world is elsewhere
sudo systemctl enable --now creature-body
journalctl -u creature-body -f
```

The World Viewer's Entities panel shows `character:beaky` with its body facts; ask her "how
warm is your board?" and she reads the number.
