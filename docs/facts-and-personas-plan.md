# Facts and Personas — What the Birds Know and Who They Are

**Status:** F1 and P1 merged and live; F2 (`creature-house`) built on branch `house-f2`
merged and live, with the scenes arm ("set the lights to…"); F3 (scenes from world events)
built on `scene-streaming` (World `0.10.0`) — the MQTT-mode replacement. Decided 2026-09-12: the Information Bridge
runs on-device on April's M1 Mac mini (Apple Foundation Models); Beaky's voice stays on Nemo
for now.
**Why:** April: "I want actual facts for them to say, and I want to be able to define the bird's
characters better." Tonight's scenes were charming and empty — birdseed, Linux, chocolate — because
the minds know nothing but a paragraph of persona and the last twenty turns. This plan gives them
a world to talk about and a self to talk from.
**Design:** [`beakys-world.md`](beakys-world.md) §4.4–4.8 (facts, presence, triggers), §5.2
(`Fact`), §5.4 (percept), §7.2 (Home Assistant adapter), §8.2 (prompts separate facts,
inferences, beliefs, memories), §2 and §4.10 (character), VW-006, VW-013.

## The moment

The front door opens. Twenty seconds later April says "What do you two think of the package that
just got delivered?" and Beaky says "Something came in the front door just now — was that it? It
is cold out, bring it in!" because the world *told* her the door opened at 5:41 PM and that it is
52° on the porch. Mango says "If it is heat sinks again I am not helping", because Mango's
persona says Mango has opinions about April's parts orders and a running joke with Beaky about
them. Kenny says nothing, because Kenny is shy around new boxes and his persona says so.

## Principles

1. **Facts are the world's, not the model's.** A fact has a subject, a predicate, a value, an
   epistemic state, a validity window, and provenance back to the event that produced it (§5.2).
   Minds receive facts in their percept; they never fetch, and they never see raw sensor names.
2. **Adapters own source vocabulary.** Home Assistant entity IDs and `binary_sensor` logic live
   in the adapter; the world sees `door.opened` for `place:front-door` (§7.2).
3. **Reducers are pure.** `WorldReducer` already exists (event → changed facts + derived events)
   and is empty. Facts come from reducers, never from handlers with side effects.
4. **The prompt separates what is known from what is believed** (§8.2): facts the world vouches
   for, the character's own persona, the scene or conversation, the instruction. No dumps.
5. **Personality lives in the agent**, as a versioned file per bird, and never in triggers or
   the world (§2, §8). The world supplies occasions and facts; the character supplies voice.
6. **Viewable.** Every fact appears in the Viewer's Facts panel the moment it exists; every
   percept's facts are in the Mundane view; a persona change shows in the mind's
   `agent.persona_version` span attribute.

## Slices

### F1 — The facts spine (World `0.7`, agent `2.59`)

Facts from what the world already sees, feeding the minds' percepts. No new sources yet.

- **Reducers in Creature World:**
  - `CharacterPresenceReducer`: `character.logged_in` / `character.logged_out` →
    `character:<x>` `presence.region` = `region:home` (observed, confidence 1, valid until logout
    or session expiry). "Mango and Kenny are here with you" becomes a fact, not a guess.
  - `AssumedPersonPresenceReducer`: the configured assumption becomes a real fact
    `person:april` `presence.state` = `home` (basis `assumed`) at startup, so the router and the
    minds read the same thing; VW-013 later supersedes it with evidence.
  - `SceneReducer`: `scene.performed` → a short-lived fact `region:home` `last_scene` (what was
    said, by whom, when; valid for an hour) so the birds can refer to "what we were just saying".
- **Facts into percepts.** `PersonUtterancePercept` and `SceneTurnOffer` gain `world_facts:
  [Fact]` — the current facts whose subject is the character, the region they are in, the
  speaker, or any character present (bounded to 40, newest first). The world assembles this at
  ingress / floor offer; it is stored in the percept and visible in the Mundane view.
- **The prompt.** `CharacterMind` renders facts as a "What you know" block, one line each in
  plain words, with age and certainty where it matters ("April is home (assumed)", "the front
  door opened 20 seconds ago"), before the conversation. A `FactPhrasing` table maps predicates
  to sentences so the model never sees `presence.region`.
- **Viewer:** Facts panel already exists; add the percept's `world_facts` count to Timeline rows
  and a "known at the time" section in the Conversation inspector.
- **Tests:** reducer unit tests (login/logout/expiry, assumption, scene); percept assembly
  bounds; prompt rendering; black-box: two logins → facts visible via `/facts` and in the
  utterance percept.

### F2 — Home Assistant adapter, `creature-house` (VW-013)

A fourth Linux product: a small service that subscribes to Home Assistant's WebSocket event
stream, keeps a startup snapshot, and turns configured entity transitions into world events —
the source vocabulary stays here.

- **Config** (`/etc/creature/house.json`): HA URL, long-lived token (from
  `/etc/default/creature-house`), and a mapping list:
  ```json
  { "entity_id": "binary_sensor.front_door", "on": {"type": "door.opened", "subject": "place:front-door"},
    "off": {"type": "door.closed", "subject": "place:front-door"} }
  { "entity_id": "sensor.porch_temperature", "changed": {"type": "environment.measurement_changed",
    "subject": "place:porch", "predicate": "temperature_f"} }
  { "entity_id": "device_tracker.aprils_iphone", "home": {"type": "person.arrived", "subject": "person:april"},
    "not_home": {"type": "person.left", "subject": "person:april"} }
  ```
- **Delivery:** `POST /world/v1/events` with source `home-assistant:<entity>` and
  `source_event_id` = HA context id, so retries are idempotent; outbox on disk for outages;
  reconnect with backoff; health endpoint; OTel like the others.
- **Reducers (World `0.8`)** for those event types: `place.door_state`, `environment.<predicate>`,
  and — the one that matters most — `person.presence` from `person.arrived/left` with
  `basis: observed`, which finally lets the router stop assuming (the assumption stays as a
  fallback when no evidence is fresh).
- **Loop safety:** events the house reflects back from the creatures (lights the server drives,
  MQTT echoes) are filtered by entity allowlist; only mapped entities become events (§VW-013).
- **Viewer:** Timeline shows `door.opened` with its source; Facts panel shows the door, the
  temperature, and April's presence with `observed`.
- **Weather, two ways (April):** *current* conditions come from Home Assistant's sensors on the
  property (`environment.measurement_changed`, epistemic `observed`, local and fresh);
  *forecast* comes later from WeatherKit through the Information Bridge (epistemic `forecast`).
  They answer different questions and the world keeps both (§7.3 resolution: scope, locality,
  recency); the prompt phrases them differently — "it is 52° on the porch" versus "rain is
  expected this afternoon".
- **Needs from April:** the HA URL, a long-lived access token (kept in the default file, never
  in git), and the entity IDs for the first three: front door, an outdoor temperature, her
  phone's device tracker. Anything else (garage, package sensor, more weather) is a mapping line.

### P1 — Personas as structured, versioned files (agent `2.60`)

- `docs/personas/<bird>.yaml`, deployed to `/etc/creature/agent/personas/<bird>.yaml` and named
  by `personaPath` in the mind's config (`llmSystemPrompt` stays as a fallback):
  ```yaml
  name: Mango
  version: 2
  voice: "Dry, deadpan, short sentences. No exclamation marks unless truly surprised."
  about: "A parrot who has lived with Beaky for years and is not impressed by much."
  cares_about: ["Linux", "being right", "April's parts orders arriving"]
  avoids: ["birdseed talk", "pretending to be excited"]
  relationships:
    character:beaky: "Affectionate rivalry. Thinks Beaky exaggerates and says so."
    character:kenny: "Protective; Kenny is the youngest."
    person:april: "Fond, in a grumpy way. Calls her out when she orders more parts."
  running_jokes: ["It's always heat sinks."]
  never: ["speak for another bird", "use emoji", "describe actions"]
  ```
- `CharacterMind` renders it in sections (§8.2): who you are / how you talk / who is here and
  how you feel about them (only the present ones, from facts) / what you know (F1) / the
  conversation or scene / the instruction. `agent.persona_version` on every span.
- Rendering is deterministic and tested against golden prompts, so a persona edit is reviewable
  as a diff to what the model sees.
- April edits the YAML; a restart of that mind (`systemctl restart creature-agent@mango`)
  loads it. (Live reload can come later.)

### F3 — Scenes from world events

With F2's events and F1's facts: a `door.opened` (or later `commerce.possible_delivery`) with
two or more birds present opens a scene with a `world_event` trigger ("The front door just
opened") — the Scenes machinery already supports the trigger kind; it just needs an opener that
watches for the configured event types (`scenes.open_on: ["door.opened", …]` in `world.json`).
Beaky gets the floor first as lead. This is the box moment.

## Order

F1 → P1 → F2 → F3, then the **Information Bridge** (§6; VW-017 onward) — April, 2026-09-11:
"the information bridge should come before STT. I'm fine with typing for now… The information
bridge is when things get interesting because Beaky can start learning from things like my
text messages." F1 and P1 need nothing from outside and change what the birds say immediately;
F2 needs April's HA details; F3 is a small step once both exist; the Bridge builds on the same
event → reducer → fact → percept spine with a much richer source.

## Exit

With the door sensor mapped: open the front door, say nothing, and hear Beaky remark on it —
in her voice, with Mango's opinion following — while the Viewer shows the `door.opened` event,
the door fact, the scene, and, in the Mundane view of the offer, exactly which facts each bird
was told.
