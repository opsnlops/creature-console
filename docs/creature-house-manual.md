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
| `person` | `person.*` / `device_tracker.*` | `home` → `person.arrived`; anything else → `person.left` (moving between two away zones is neither). And, since `0.5.0` (#248), where the phone is: when the state carries `latitude`, `longitude` and `gps_accuracy` (a GPS source; a network tracker gives no accuracy and is no fix), `person.located` with them, when the fix moves 25 m, gets twice as sure, or is 10 minutes old |
| `measurement` | `sensor.*` with a number | → `environment.measurement_changed` with `predicate` and `value`; a move smaller than `minimum_change` **from the last value the world was told** is dropped (so a thermometer creeping 0.2° at a time still gets announced once it has drifted a degree; `0.1.1`). `minimum_change_percent` adds a proportional bar - a move must clear both - for quantities spanning orders of magnitude: daylight is 0–100,000 lux, and no one step serves dusk and noon (`0.4.0`) |
| `detection` | `binary_sensor.<camera>_person_detected` etc. | `on` → `camera.person_seen` / `vehicle_seen` / `animal_seen` (`detects`); `off` after an `on` that lasted at least `gone_after_seconds` (default 600) → `camera.person_gone` / `vehicle_gone` with `after_seconds` (`0.2.0`: the cleaners' car leaving after two hours is a moment; a car that passed is nothing twice; never for animals); a camera already seeing something at startup is not news. At startup the adapter also announces `camera.watching` for each such place (`0.1.2`), so a camera that has seen nothing is a fact the birds can state — "The cameras at the front door and the driveway have seen nobody and nothing in the last ten minutes" — rather than a shrug |

The packaged `house.json` maps April's weather station and power monitor as measurements —
`humidity_percent`, `wind_mph`, `rain_today_in`, `pressure_hpa`, `pm25_ugm3`, `light_lux` on
`place:outside` and `power_w` on the house — and the glossary has words for each ("It is windy outside: about 18
miles per hour", "It has not rained today", "The air outside is clean", "The house is drawing
about 2.2 kilowatts right now"). Daylight (`light_lux`, from `sensor.outside_light_level`) is told on a halving or doubling
(`minimum_change` 10, `minimum_change_percent` 50) and is glossed with bands - under 10 dark, dusk
and dawn in the tens to hundreds, an overcast day in the thousands, sunshine in the tens of
thousands. New predicates are just a mapping line plus a meaning in `WorldFacts.meanings`.

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

With `scenes.offer` off, the house still follows Home Assistant and tells the World everything; it just has no world stream to follow (before `0.7.2`, #277, it exited at startup). With `scenes.offer` on, the adapter posts `house.scenes_offered` at startup (the friendly names
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

A stop (`systemctl stop`, an upgrade) cancels the Home Assistant socket and the world
stream and returns within a second (`0.1.4`; `TimeoutStopSec=15` remains as the backstop).
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

## The TV (`0.3.0`)

A mapping of kind `media` turns a Home Assistant `media_player.*` into words on its room, with
a `predicate` like measurements have:

```json
{ "entity_id": "media_player.family_room_tv_samsung", "subject_id": "place:family-room", "kind": "media", "predicate": "tv" },
{ "entity_id": "media_player.family_room_receiver", "subject_id": "place:family-room", "kind": "media", "predicate": "source" }
```

The words: a device that is only on is `"on"`; a receiver says its source and volume in tens
(`"Apple TV, volume 40%"`); a player with something on it says the app and title
(`"YouTube: <title>"`, `"Music: <title> by <artist>"`, `"(paused)"`). Idle with a title left
over from last time is not playing. The house sends `media.changed` when the words change (a
new video under the same `playing` state counts; a nudge of the volume knob inside ten percent
does not), and `null` when the device goes off, standby, or unavailable, so the world's
`media.<predicate>` fact is never stale; at startup every media player says its state once,
off included. It is state, not story: never a happening, never a scene.

Home Assistant had no Apple TV entity on 2026-09-22, so the title of what is playing needs its
Apple TV integration (Settings → Devices & services → Apple TV, pair with the PIN on screen);
then one more line maps it with `"predicate": "playing"`. The family room must be a place in a
region the birds are in (`place:family-room` in `region:home`, packaged world.json `0.41.0`).
This is also the fact the microphones will read: in a room where media is playing, an
utterance will need to begin with a bird's name.

## Never stale (`0.3.1`)

`minimum_change` keeps a measurement's small wobbles from being news, measured from the last
value the house told the world. On its own it can leave a fact hours old: the power meter sat
at 1,647 W for an evening because the draw never moved a whole kilowatt away from it. Each
measurement also has `maximum_age_seconds` (default 900): once the world's value is that old,
the next change is told whatever its size. Big swings still go at once; an unchanging sensor is
not re-told (its value is still right).


## A team's games (`0.6.0`)

A mapping of kind `game` reads a Home Assistant **Team Tracker** sensor
([vasqued2/ha-teamtracker](https://github.com/vasqued2/ha-teamtracker), from HACS; League `NFL`,
Team `SEA`) into a team's games (#269). The World stays offline; Home Assistant polls ESPN.

```json
{ "entity_id": "sensor.seattle_seahawks", "subject_id": "team:seahawks", "kind": "game" }
```

Team Tracker shows one game at a time: the last one, `POST`, until the next is within twelve
hours, then that one, `PRE`, then `IN` while it is played. It looks every 10 minutes, and every
5 seconds during a game. The house reads it as its source writes it: the kickoff (`date`) has no
seconds (`2026-11-03T01:15Z`), the scores are strings (`"20"`, `"2(4)"` after a shootout), and
`team_winner` is a bool once the game is final.

The house tells the World each game once at each stage:
- `game.scheduled`: published.
- `game.started`: under way.
- `game.final`: both scores and `won` / `lost` / `tied`. It also has `ended_at` when the house
  saw it turn from under way to final, which is the whistle to within seconds.

Each event is keyed by its game (`game:<kickoff>:final`), not by Home Assistant's context. A
restart's snapshot of a final the World already heard live is the same event and changes
nothing, so its `ended_at` survives. A final first seen at startup fills the blank, with no
`ended_at`.

While a game is under way, each score is news:
- `game.scored`: a score went up. It has `scored_by` (the team's or the opponent's name, or
  none when both moved between two looks), both scores, the `clock` ("7:12 - 2nd") and the
  `last_play`.
- `game.score_corrected`: points were taken away and none scored, such as a touchdown
  overturned on review.

A score is keyed by Home Assistant's context, not by the score, so a touchdown overturned and
scored again is two scores. A restart mid-game tells the game under way with its score, and
no score event.

**Possession** (`0.7.0`, #272). While the game is under way the house also reports the ball
changing hands as `game.possession`. Team Tracker's `possession` is ESPN's id for the side
with the ball; matched against `team_id` / `opponent_id`, it becomes the team's or the
opponent's name. The event carries both scores, the clock, the `last_play` and
`down_distance` ("1st & 10 at SEA 25"). Neither of these is news:
- ESPN saying nothing between plays
- the downs moving while the same side has the ball

A score and a change of hands in one update is reported as the score, carrying the new
`possession`. Every game event under way carries `possession` and `down_distance`.

**First downs, flags and reviews** (`0.8.0`, #287). Under way, the house also reports:
- `game.first_down`: the down went back to `1st` for the side that already had the ball
- `game.penalty`: an enforced foul in ESPN's write-up (`PENALTY on SEA-…, False Start, 5
  yards, …`), with `penalty_on`, `foul` and `yards`. Declined and offsetting flags are not news.
  `penalty_on` is the side's name when ESPN's short name matches `team_abbr` / `opponent_abbr`,
  and ESPN's short name otherwise.
- `game.reviewed`: a coach's challenge or the booth's review, once decided, with
  `challenged_by` (absent for the booth) and `outcome` (`reversed`, `upheld`, `stands`). ESPN
  never shows the flag being thrown.

- `game.play` (`0.9.0`): any other snap, once the down moves; a write-up that moves no down,
  such as a timeout, is nothing

Every game event under way carries `team_abbr`, `opponent_abbr`, `team_timeouts` and
`opponent_timeouts` (`0.10.0`), for the World's scoreboard. A score carries `points`, how many
it added (`0.9.1`), and an event whose `last_play` the World
already heard leaves it out: ESPN moves the score before it writes the play up.

One play is one event, the biggest: a score, the ball changing hands, a review, a flag, a first
down, then any other play. Each needs a `last_play` the World has not heard; a repeated look is nothing.

The side last known to have the ball outlives an update that names nobody (`0.7.1`). ESPN
names nobody on a scoring play. In 0.7.0 the house remembered that blank, so the kickoff that
followed, with the scorers still on the ball, read as a change of hands: "Seattle Seahawks now
has the ball" after their own field goal. `HouseTranslator.remembered` keeps the last known
`possession` in what the announcer remembers.

A score happens at Home Assistant's `last_updated` (`0.6.1`, #271). A score changes only the
sensor's attributes, and `last_changed` moves only when the state does, so in 0.6.0 every score
of the Bears game carried the kickoff's time. The stage events are state changes and keep
`last_changed`.

These are not news:
- the odds or the clock moving under the same state
- a bye or `NOT_FOUND`
- the sensor going unavailable and coming back as the same final

A game moved to another kickoff is told again, as that game.
