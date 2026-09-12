# The Flock — Several Minds in One World

**Status:** C1 (#159) and C2 (#161) merged and live on fuzzball 2026-09-11; C3 on `flock-c3-communicator`.
**Design:** [`beakys-world.md`](beakys-world.md) §8.3 (multi-character scenes), §8.5, §11.2,
Phase 9; the "one mind per character" and "agent collisions" notes in
[`beaky-mind-plan.md`](beaky-mind-plan.md#after-this).
**Why now:** April: "A virtual world with just one character is boring… by doing this now it'll
stop us from baking in some bad assumptions later about just one character. Beaky will always be
the lead, but she doesn't live here by herself."

## The moment

A box lands on the porch. The world knows (VW-013 / VW-018, later). Beaky, in the living room,
says "April, I think the servos you ordered are here!" Mango, across the room, chimes in: "Or it's
more heat sinks. It's always heat sinks." Beaky: "You don't know that." April hears two birds
having a real exchange, rendered as one performance where each reacts to what the other said —
and the Communicator on her phone shows both lines, with both names.

Or April, on the couch, says "Mango, what do you think of the new servos?" and Mango — not Beaky
— answers, in Mango's voice and Mango's opinion, while Beaky lets it pass or adds a word.

## Principles (the assumptions we are refusing to bake in)

1. **One mind per character, every character its own process.** Beaky never speaks for Mango.
   Mango's words come from a `creature-agent` that is Mango: its own persona, its own
   `creatureId`, its own cursor, its own memories later. Same binary, different configuration.
2. **Beaky leads.** The world's defaults point at her: an utterance with no named addressee is
   hers; she opens scenes; she gets the floor first. Leadership is a world rule, not a special
   case in the code.
3. **The world coordinates; minds decide.** Who is present, whose turn it is, when a scene is
   over, and how it is performed are world decisions and world records. Whether a character has
   anything to say, and what, is the mind's. This is what keeps three minds from talking over
   each other without any mind knowing about the others' internals.
4. **Nothing is addressed to "the bird".** Conversations, deliveries, percepts, stage decisions,
   and the Communicator all carry a `character_id`. There is no default character below the
   world's leadership rule.
5. **Two performance shapes, chosen by the world.** A single character answering April keeps
   today's fast path (stream sentences while the model thinks, ~2 s to first words). A scene with
   more than one voice is composed turn by turn in text at mind speed, then rendered as one
   jointly conditioned performance through Creature Server's dialog pipeline (§8.3: "do not
   build live turn-by-turn improvisation first"). A streaming multi-character session on the
   server is a later upgrade with a spec of its own (below).
6. **Collisions are impossible by construction.** Two processes claiming to be Beaky is April's
   Second Life scar. A character login in the world makes the second one a spectator.
7. **Characters log in, to a region.** Following Second Life: a character is logged into at most
   one region at a time, and "who is present" for a scene is "who is logged into this region".
   Today there is one region (`region:home`); the building April is putting up for the
   characters will be another. Logins *are* character presence — the world needs no other
   presence system for the birds until proprioception arrives.

## Slices

### C1 — Many minds on one host (agent `2.57`, World `0.5`)

- **systemd template unit** `creature-agent@.service`: `creature-agent@beaky`,
  `creature-agent@mango`, … each reading `/etc/creature/agent/<instance>.yaml` (agent
  configuration moves beside the World's under `/etc/creature`) and
  `/etc/default/creature-agent-<instance>` (after the shared default file), with
  `StateDirectory=creature-agent/%i` so each mind keeps its own cursor. The existing
  `creature-agent.service` stays for MQTT mode on production; the package ships both.
- **Character login.** `POST /world/v1/characters/{character_id}/login` with the mind's
  instance identity (host, pid, `creature_id`) and the region it inhabits (`region:home` for
  now, from config); the world grants a session with a TTL (30 s) the mind heartbeats
  (`…/heartbeat`), and `…/logout` on graceful shutdown. Stage decisions, performances, and
  responses for a character require its live session; a second process for the same character
  is told `logged_in_elsewhere` and follows the world read-only (logs, metrics, no turns) until
  the session lapses. A character is in one region at a time; logging into another region ends
  the first session. Logins are world records and the first character presence: **the Viewer
  gets a Characters panel** — who is logged in, to which region, since when, from which host,
  last heartbeat, last turn.
- Config per character: `characterEntityId`, `creatureId`, `llmSystemPrompt` (persona),
  `personEntityId` (who they answer by default; still April), `stage`. Personas live in the
  agent (§2, §8), one file per bird, versioned in `docs/personas/` alongside the plan.
- **Exit:** `creature-agent@beaky` and `creature-agent@mango` run side by side on fuzzball;
  the Viewer shows both logged into `region:home`; a second `creature-agent@beaky` started by
  hand shows `logged_in_elsewhere` and never speaks; Mango's mind answers "Mango, are you there?" in the room
  with Mango's creature (C3 makes the addressing real; in C1 the test is a hand-cast utterance
  addressed to `character:mango`).

### C2 — Scenes: the world gives the floor (World `0.6`, agent `2.58`)

The unit of multi-party exchange is a **scene**, a world record:

```
scene: { scene_id, opened_by (event / utterance), participants: [character_id],
         place_id?, turns: [{ character_id, text, response_id }], state: open|rendering|performed|abandoned,
         performance: { provider_reference, outcome } }
```

- **Opening.** A scene opens in a region when a percept there has more than one candidate
  listener: an external event (the box) with several characters logged in, or a person utterance
  addressed to a character while others are logged in. Whoever is logged into the region is
  present — Beaky and Mango most days; Kenny or Caroll whenever their minds are up.
- **The floor.** The world offers the floor to one participant at a time with a
  `scene.turn_offered` percept (the scene so far, the trigger, who else is present). Beaky
  first, then the others in a world-chosen order, round after round; a mind answers within a
  deadline (5 s) with a turn or a `pass`. The birds may chat as much as they like, until a full
  round of passes, or the cutoff: `max_turns` (12) or `max_spoken_seconds` (~90 s of composed
  speech, estimated from the text) — configured per world, so April can tune the feel. Minds
  keep their current guardrails (stale, not addressed → pass); silence stays a decision.
- **Performing.** A closed scene with one turn from one character is performed exactly as today
  (the fast path is the degenerate scene; nothing about "Hi April" changes). A scene with two or
  more voices is rendered by the **world** through Creature Server's existing ad-hoc dialog
  endpoint (`POST /api/v1/animation/dialog` with inline `turns`, `persistence: "adhoc"` — a TTL
  collection the server cleans up, so no clutter — `autoplay: true`, and the parent trace); the
  world becomes a Creature Server client for scenes, which is where §17 always pointed. The
  render is an async job; its completion comes back as the scene's performance record. Every
  turn is also a conversation item, so the Communicator and history show the exchange.
- **Timing.** Text composition at mind speed (2–3 s per turn) plus a dialog render (~5–10 s)
  means a two-bird exchange about the box plays ~15 s after the trigger. That is fine for
  reactions to the outside world; direct questions to one bird keep the ~2 s path.
- **The Viewer gets a Scenes panel:** open scenes with the floor holder and the deadline, the
  turns as they land, the performance, and why a scene closed.
- **Exit:** a hand-cast `package.delivered` event with Beaky and Mango assumed present produces a
  two-turn scene, rendered and played through both creatures, visible turn by turn in the Viewer
  and as one Honeycomb trace event → World → Beaky's mind → Mango's mind → Creature Server.

### C3 — A Communicator for the flock (Communicator `0.3`, gateway `0.2`)

- One **house conversation** per person, `conversation:april-house`, that every character may
  speak in — Beaky, and whoever feels like joining (April: losing the first night's history to
  the rename is fine, "we're just playing around"). `conversation:april-beaky` stays readable.
  Items already carry `author_id`; the app shows the author's name and colour per character
  (`0.2.0`).
- **Addressing.** April's message names a character or not: "Mango, …" / "@Mango" → Mango;
  otherwise Beaky, by the leadership rule. The addressee resolution is a world rule
  (`PersonUtteranceIngress`), not a gateway or app rule, so STT later gets it for free. A message
  to one character while others are present opens a scene (C2) so the others may chime in; the
  world keeps the answer count sane (the addressee always gets the floor; others may add at most
  one turn).
- Beaky Communicator's title, icon, and settings stop assuming one bird; the app subscribes to
  the house conversation and shows who is speaking. Push and quiet hours (later VW-028 work)
  apply per person, not per character.
- **Exit:** "Mango, do you like the new servos?" from the phone is answered by Mango, aloud and
  in the app, with Beaky's optional one-liner after; the Viewer shows the scene.

### Creature Server — streaming multi-character dialog (spec, issue opened)

The ad-hoc dialog pipeline renders a *complete* scene (verified: `POST /api/v1/animation/dialog`
with `persistence: "adhoc"` exists on the server, TTL-cleaned, autoplay-able). That is enough
for C2, at ~15 s from trigger to playback, which April accepts while we learn. To get back to
~2 s for multi-character exchanges the server needs a streaming session with several creatures,
the way `ad-hoc-stream` streams one. Proposed shape, opened as an issue on `creature-server` for
server-side work:

- `POST /api/v1/animation/dialog-stream/start` `{ creature_ids: [...], resume_playlist }` →
  `session_id`.
- `POST …/dialog-stream/turn` `{ session_id, creature_id, text }` — one sentence or turn for one
  creature; the server synthesizes it in that creature's voice (ElevenLabs single-voice, since
  Text-to-Dialogue needs the whole scene) and plays it in order, lip-synced on that creature's
  channels, while the others hold an idle/listening pose.
- `POST …/dialog-stream/finish` `{ session_id }` → animation ID for the whole exchange, and the
  exchange recorded as one ad-hoc animation with all participants' tracks.
- Trace: the parent trace header on every call, as today.

Trade-off: streamed turns are single-voice renders that do not react to each other in tone the
way Text-to-Dialogue does; the complete-scene path stays the choice for pre-composed scenes, and
the streaming path is for when latency matters more than joint conditioning. The world chooses
per scene.

## What changes in what we have built

- `WorldPerceptSubscriber` already filters by `characterID`; per-instance cursors make it
  per-character. `CharacterMind` gains `pass` as a decision and a `scene.turn_offered` percept.
- `CharacterDeliveryRouter` becomes scene-aware: a stage decision is per scene, not per
  response, when the scene has several voices; `physical_speech` for a scene means "the world
  will render it", not "you may stream".
- The Viewer gains Characters and Scenes panels; the Conversation panel shows several authors.
- Personas move out of `llmSystemPrompt` strings in YAML into versioned persona files, one per
  bird — the first step of the personalities phase, taken now because we need two of them.

## Decisions (April, 2026-09-11)

1. **Beaky + whoever is online.** Four parrots today — Beaky, Mango, Kenny, Caroll. Beaky and
   Mango are usually up; Kenny or Caroll join whenever their minds are logged into the world.
   "Logged into Creature World" is the presence system for characters.
2. **Regions, Second Life style.** All four are in one spot today; in a few months the characters
   move into their own building. A character is logged into one region at a time; scenes and
   presence are per region. One region (`region:home`) for now, modelled from day one.
3. **One conversation with everyone in it** — Beaky and whoever feels like joining; maybe no
   one else does, depending on how the agents feel.
4. **Chat freely, with a cutoff** so a scene cannot run for several minutes.
5. **Server:** ad-hoc dialog rendering already exists (no ticket needed); the streaming
   multi-character session is wanted to get back to ~2 s, but going long is fine in this phase.
   The spec is filed on `creature-server` for a second Claude to build.

## Suggested order

C1 first (it is mostly packaging and one world record, and it makes every later slice
two-character from day one), then C2 (the magic), then C3 (the phone catches up). Facts
(VW-006/VW-013) can proceed in parallel; the box has to be a world event before Beaky and Mango
can argue about it.
