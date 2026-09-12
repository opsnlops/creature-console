# Beaky Virtual World

## Architecture and Implementation Handoff

**Status:** Implementation underway; World and Communicator transport are on production; Creature World accepts character turns; Beaky answered April with her own words (Mistral Nemo) on fuzzball tonight (branch `vw-014-beaky-mind`)
**Revision:** 2026-09-10 (late night)
**Primary goal:** **Make Beaky really be April’s familiar.**  
**Experience goal:** **Make the house feel alive.**  
**Stack mantra:** **The world happens. The agents notice. The server performs. The controllers obey.**

---

## 0. Current implementation handoff — 2026-09-11

This section is intentionally operational and time-sensitive. It gives the next engineer or agent
enough context to continue without reconstructing the implementation from chat history. **Keep it
current in the same commit as the code it describes.**

### 0.1 Repository and review state

- `main` is at `d43fcbc`. Merged since the 2026-09-10 handoff: PR #142 (Beaky's mind), #143
  (gateway shutdown, #141), #145 (`--no-start` on upgrade), #147 (user guide), #148 (context
  window opens with April's turn, `2.55.2`), #150 (utterances carry April's trace, #149), #152
  (Beaky's reply is delivered inside the `agent.turn` span, `2.55.3`).
- PR #153 (World Viewer, VW-010 #101, World `0.3.0`) merged 2026-09-11 afternoon; the Viewer
  is verified live against fuzzball. Manual: [`docs/world-viewer-manual.md`](world-viewer-manual.md).
- PR #155 (Beaky's voice in the room, VW-016 #107, World `0.4.2`, agent `2.56.1`, the
  MongoKitten fork, #156, #157) merged 2026-09-11 evening; Beaky is heard on fuzzball.
- **Off script since 2026-09-11 evening: the flock.** April: a world with one character is
  boring; four parrots (Beaky, Mango, Kenny, Caroll) should inhabit it, Beaky leading. Plan:
  [`docs/flock-plan.md`](flock-plan.md) (principles, slices C1–C3, April's decisions, the
  server streaming-dialog spec at creature-server#186).
- PR #159 — **C1, many minds on one host** (#158): Creature World `0.5.0`, `creature-agent`
  `2.57.0`. Green except one Viewer test double the C2 branch also fixes (uncommitted in a
  worktree at the time of writing; needs April's key).
- Active branch: `flock-c2-scenes` (stacked on C1) — **C2, scenes: the world gives the floor**.
  Creature World `0.6.0`, `creature-agent` `2.58.0`. Built and tested while April was at the
  store; not yet committed (YubiKey).
- **April's definition of done (2026-09-11):** a feature is complete only when it works live
  *and* is viewable in World Viewer. Plan the Viewer surface into every slice.
- #154 (replies drifting into `Beaky: "…"` script format) is fixed in `2.55.4`: the mind stores
  only her words.
- #156 (World refused every utterance once `conversation:april-beaky` passed 100 items — the
  percept carried the whole history into a 100-item contract) is fixed on this branch: the
  ingress now carries the newest 100.
- #144 fixed on `fix/162-bare-silence` (World `0.6.0`+, gateway `0.1.4`, agent `2.58.1`):
  upgrading a running service restarts it, template instances included; fresh installs of
  World/gateway still wait for the operator.
- Open follow-ups: #132 (gateway collapses World 4xx→503), #133 (`conversationItem` camelCase
  key), #146 (mqtt conffile), #151 (Communicator double POST on send).

### 0.2 What is running now

| Product | Version | Where | Notes |
| --- | ---: | --- | --- |
| Creature World | `0.4.2` fuzzball / `0.2.2` prod | fuzzball (`10.69.66.1:8001`), production | `0.4.x` adds `/stage`, `/performances`, assumed presence (on, for April), the 100-item window (#156), and the MongoKitten fork |
| Communicator Gateway | `0.1.3` | production and fuzzball `:8002` | exporting to Honeycomb `production` |
| Beaky's mind | `creature-agent 2.56.0`, `mode: world`, `stage: physical` | **fuzzball only** | speaks through production Creature Server (`creatureId 4754fc0e…`); Mistral Nemo via llama-server at `10.69.66.4:1234`; `2.56.1` (this branch, #157) not yet installed; set `localLlmMaxTokens: 400`; production keeps `2.54.1` in `mqtt` mode (see 0.4) |
| World Viewer | `0.1.0` | April's laptop, run from Xcode | read-only; points at fuzzball or production; delivery chips show route · reason · presence (basis) · outcome |

**Verified live so far:**
1. Beaky's first turn (cast by hand) landed on April's phone from fuzzball, then production.
2. **Beaky's first words of her own** on fuzzball, thinking with Mistral Nemo over the canonical
   conversation; her mind rode through World restarts on its own. She shrugs (`[silence]`) at
   things that were not questions to her — April likes that.
3. One Honeycomb trace per utterance, end to end: phone → gateway → World → `agent.turn`
   (consider → `llm.mistral.generate` → `creature.world.respond`) → World router.

### 0.3 What this branch adds — the flock, C2: scenes (`flock-c2-scenes`)

- **WorldCore:** `Scene`, `SceneTrigger`, `SceneTurn`, `SceneFloor`, `SceneTurnOffer` (event
  `scene.turn_offered`), `SceneTurnSubmission`, `SceneLimits`, and `SceneService` — opens
  (addressee first, then the others), offers the floor with a world-timer deadline
  (`scene.floor_expired` → pass), accepts a turn or a pass (idempotent by `response_id`;
  `not_your_turn` when the floor moved), closes on the cutoffs (everyone passed / max turns /
  max spoken seconds), interrupts an open scene when a new one opens in the region, and hands
  closed scenes to a `ScenePerforming`. `PersonUtterancePercept.scene_id`; `ScenePlanning` at
  the ingress decides scene-or-solo *before* the percept is stored. Dates the world stamps go
  through `WorldJSON.wireDate` (millisecond) so identity checks survive MongoDB.
- **World `0.6.0`:** `PresentCharactersScenePlanner` (a scene when >1 character is logged into
  the addressee's region), `MongoSceneRepository` (`scenes`, migration v7), the floor-deadline
  watcher on the world stream, spoken turns saved as conversation items and published to the
  Communicator, `StreamingScenePerformer` (server-you shipped `dialog-stream` in creature-server
  3.46.0 / PR #187 while April shopped: a session per scene on the stage the region maps to via
  `regions.<region>.stage_id`; each turn plays ~2 s after it is composed; `finish` stitches)
  falling back to `CreatureServerScenePerformer` (complete ad-hoc dialog render, job ID recorded
  as `queued`), or `NotConnectedScenePerformer`; `scene_performance` config; routes
  `POST /scenes/{id}/turns`,
  `GET /scenes`, `GET /scenes/{id}`; `scenes` cutoffs in `world.json`. Black-box test: two
  logins → utterance → scene → turns (an impostor without Mango's session is refused) → closed →
  performance recorded.
- **Agent `2.58.0`:** subscriber delivers `scene.turn_offered` for its character;
  `CharacterMind.consider(offer)` builds a script-style transcript (persona + scene contract +
  "April: … / Mango: … / Beaky:") and returns a turn or a pass; utterances with `scene_id` are
  `in_scene` silences; `WorldMindService` posts the turn with the session.
- **Viewer:** Scenes panel (trigger, participants, floor + deadline, turns/passes, close reason,
  performance), refreshed on `scene.*` events.
- **Not yet:** scenes triggered by world events (the box) — only person utterances open scenes
  until VW-013 brings house events; job completion tracking (the render is recorded `queued`);
  the Communicator still shows one bird's name (C3).

### 0.3a What PR #159 adds — the flock, C1: many minds on one host (#158)

- **Character login in the World (`0.5.0`).** `POST /world/v1/characters/{id}/login` with a
  region and the mind's instance (host, pid, creature, version); 30 s sessions kept alive by
  `…/heartbeat`; `…/logout`; `GET /world/v1/characters`. One mind per character, one region per
  character (Second Life style; `region:home` today, the characters' new building later).
  A second process is told `logged_in_elsewhere` (409). `character.logged_in` /
  `character.logged_out` world events. `/stage` and `/performances` carry `session_id` and are
  refused for a mind that does not hold the character — collisions are impossible by
  construction. `CharacterSessionService` (WorldCore), `character_sessions` collection
  (migration v6).
- **Agent `2.57.0`.** `WorldCharacterSession` logs in before the mind follows the world,
  heartbeats every 10 s, spectates (follows nothing, says nothing, retries every 15 s) when the
  character is held elsewhere, logs out on shutdown. `regionEntityId` config. Template unit
  `creature-agent@<instance>` (`/etc/creature/agent/<instance>.yaml`,
  `/etc/default/creature-agent-<instance>`, `STATE_DIRECTORY` per instance); agent config
  moves to `/etc/creature/agent.yaml` beside the World's (conffile carried across).
- **Viewer:** Characters panel (active/expired/logged-out, region, host, pid, version,
  heartbeat), refreshed from `character.*` events.
- **Personas** as versioned files under `docs/personas/` (Beaky, Mango draft).

### 0.3b What PR #155 added — Beaky's voice in the room (VW-016), merged

- **The world decides, the mind performs.** `POST …/stage` gives the mind a durable, idempotent
  `CharacterDeliveryDecision` per `response_id` *before* it generates (MongoDB TTL-expires
  unused ones after five minutes; migration v5). If the route is `physical_speech`, the mind
  streams sentences to Creature Server's ad-hoc session (`CreatureServerSpeechStage`, the MQTT
  agent's path; session opened lazily on the first speakable sentence, so `[silence]` never
  makes a sound) while Mistral generates, then records the turn with `POST …/performances`
  (intent + attempt + outcome in one step, item published to Communicator subscribers). If the
  route is the Communicator, today's `/responses` path runs unchanged. `/responses` honours a
  prior stage decision instead of re-reading presence.
- **Assumed presence.** `presence.assumed` in `creature-world.json` (`AssumedPresenceProvider`)
  puts April home and audible; `PersonPresence.basis` (`assumed` / `inferred` / …) is recorded
  on every decision and shown in the Viewer's delivery chip. Presence is read before the clock
  so a reading taken "now" is never in the decision's future.
- **Mind:** `CharacterMind.Stage` (stager + room + streaming respond) is optional; without it
  the mind behaves as `2.55` (`stage: communicator_only`). The room's transcript contract tells
  Beaky April can hear her. Per-sentence validation lives in the `SpokenSentences` actor (first
  sentence decides silence and loses any speaker label, every sentence is speech-clean, the turn
  stops at the world's length limit); a model timeout keeps what was already spoken. Failures
  are recorded (`failed / physical_speech_start_failed`), never lost.
- **Viewer:** the chip reads e.g. `physical_speech · home_and_audible · home 90% (assumed) ·
  audible · performed`; hover shows the animation ID; failures show their error code.
- **Tests:** router stage/performance/refusal/honouring (WorldCore), assumed provider + config
  parsing, `/stage` + `/performances` HTTP, Mongo stage repository + TTL index, black-box
  stage→perform→stream with an assumed-presence config, mind streaming/silence/failure/
  already-delivered, service records a performance through the stub World.

### 0.3c What PR #153 added — World Viewer (VW-010), merged

- **Target `World Viewer`** (macOS, `io.opsnlops.World-Viewer`), cloned from the Communicator's
  pbxproj entries under the `WVA…`/`WVT…` ID prefixes, with its own `World Viewer Tests` target
  and shared scheme; CI's Xcode matrix builds it on macOS. Liquid Glass surfaces; Worldcraft
  vocabulary in the UI (*Scry again*, *Mundane view*).
- **Panels:** Timeline (snapshot-seeded ring of the newest 2,000 events, live via
  `/world/v1/stream`, `Last-Event-ID` resume, `resnapshot_required` handling, sequence · type ·
  epistemic · subjects · source · lag, filter), Conversation (both authors plus the router's
  delivery chip per Beaky turn: route, reason, presence seen, outcome), Facts, Timers, and an
  inspector showing any record as the JSON the World carries.
- **Creature World `0.3.0`:** `GET /world/v1/conversations/{id}/deliveries` pages
  `character_deliveries` by intent time (`after_response_id`, `limit`), through the
  application-service boundary. The wire DTOs (`WorldHealth`, `WorldEventPage`, `WorldFactPage`,
  `WorldTimerPage`, `WorldSnapshot`, `WorldDelta`, `WorldStreamFrame`, `CharacterDeliveryRecord`,
  `CharacterDeliveryPage`) moved into `WorldCore` so the server, the agent, and the apps share one
  definition; `WorldPerceptSubscriber` now decodes `WorldDelta` from there.
- **`CreatureAppSupport.WorldViewerClient`:** typed reads plus `eventStream(resumeAfter:)` over
  `URLSession.bytes` with a reusable `ServerSentEventFrameParser`.
- **`WorldStore`** (`@MainActor @Observable`) follows the world and the conversation stream through
  a `WorldScrying` seam; `WorldStoreTests` drive it against a scripted world (bound, gap-free
  resume, resnapshot, delivery join).

### 0.3a Beaky's mind (VW-014/VW-015) — merged, running on fuzzball

- `creature-agent` `mode: world` (default `mqtt` unchanged): `WorldPerceptSubscriber` follows
  `/world/v1/stream` (snapshot start, `Last-Event-ID` resume, fresh HTTP client per connection
  with a bounded connect — AsyncHTTPClient's pool backs off across requests after a refused
  connect and would otherwise hang a World restart), keeps `conversation.person_utterance`
  percepts for its character; `CharacterMind` runs deterministic guardrails (stale, not
  addressed), builds the prompt from the persona + contract + canonical
  `prior_conversation_items` (consecutive same-author turns coalesced — Mistral's template
  rejects non-alternating roles with HTTP 400), calls the local model with a timeout, validates
  (`[silence]`, empty, speech sanitizer, sentence-bounded truncation); `WorldResponder` POSTs the
  `CharacterUtteranceIntent` with `response_id = response:<consideration uuid>`; the durable
  `WorldAgentCursor` advances only after the world accepted/duplicated/rejected the turn.
- Silence is a recorded decision (log + `creature_agent.considerations.outcome` metric with
  `reason`). A replay after a crash re-asks the model; if it phrases differently the world refuses
  the second identity and the mind treats that as "already answered".
- `LocalLLMClient.respond(messages:)` takes an explicit transcript (MQTT mode's history untouched);
  the SSE delegate now surfaces non-2xx responses instead of reporting an empty answer.
- **Beaky's words are speech-clean at the source** (no emoji/symbols; digits preserved — #140):
  most replies are spoken via the ad-hoc pipeline, Communicator shows the same text.
- Tests: `CharacterMindTests`, `WorldMindServiceTests` (stub World on loopback: snapshot start,
  crash replay never posts twice, outage retries from cursor, silence advances), sanitizer tests.
  760 tests pass on macOS.

### 0.4 Deployment handoff

**`creature-agent 2.55.x` must not be deployed to production.** Production's agent (2.54.1,
`mode: mqtt`) is what makes Beaky speak aloud in reaction to house events; world mode can only
deliver through Communicator until VW-016 gives it the physical stage. It is a dev-only mind
(April's Mac or fuzzball) for now.

To run Beaky's mind on fuzzball: install `creature-agent_2.55.4_amd64.deb`
(`./build_debs.sh --arch amd64`), set `/etc/creature/agent.yaml` with `mode: world`,
`llmBackend: local`, `localLlmHost/Port` → the llama-server, `worldUrl:
http://127.0.0.1:8001/world/v1`, persona in `llmSystemPrompt` (the unit already passes
`--host/--port` for Creature Server, unused in world mode). The unit now declares
`StateDirectory=creature-agent`. Enable OTel in `/etc/default/creature-agent` to see her
thinking in Honeycomb. Presence is still `unknown`, so every reply goes to Communicator.

To put Beaky's voice in the room on fuzzball: deploy World `0.4.1` and agent `2.56.1`
(`./build_debs.sh --arch amd64`, `apt install`, restart both by hand — #144); add
`"presence": {"assumed": {"person:april": {"state": "home", "physically_audible": true}}}` to
`/etc/creature/world.json` and restart World; make sure `/etc/default/creature-agent` (or the
unit) points `--host/--port` at the Creature Server whose creature `creatureId` names. Type to
her from the phone and she answers through the creature. Remove the `presence` block to send her
back to the Communicator.

### 0.4b The first scene — 2026-09-11 21:21 PDT

"What do y'all think of the package that just got delivered?" from the phone, Beaky and Mango
logged into `region:home`, creature-server 3.46.0 streaming: a twelve-turn scene (closed on
`maximum_turns`), the floor alternating Beaky → Mango, performed and stitched
(`7014b5d2…`), all of it visible turn by turn in the Viewer's Scenes panel. Two things learned:
the small model writes "Silence" instead of `[silence]` and both birds said the word aloud
(#162, fixed in `2.58.1`); and twelve turns of birdseed-versus-Linux is charming once and needs
memory and personality to stay so — the cutoffs exist for a reason.

### 0.5 What is not finished

- **There are no facts in the world.** `World.reducers` is empty; Mongo holds no facts, no
  presence, no body state, no house events. Beaky's prompt contains the persona and the
  conversation and nothing else, so what she says is whatever the model came up with, not what
  the world knows. `PerceptualEnvelope.world_facts` and `relevant_memories` exist in the contract
  and are never filled. Tonight gave her a mouth and ears for April; grounding her is the
  world-visibility spine — reducers and the first presence fact (VW-006), Creature Server
  proprioception (VW-012), Home Assistant (VW-013), calendar timers (VW-018/VW-027), then memory
  (Phase 9). That is the work that turns "an LLM with a persona" into Beaky.

- **Beaky spoke in the room on 2026-09-11 at 17:32 PDT** ("Hi April! How was your day?",
  animation `be4fe551…`), staged by the world from an assumed presence, with the same words in
  the Communicator, `physical_speech · home_and_audible · assumed · performed` in the Viewer,
  and one Honeycomb trace `d304878f…` phone → gateway → World stage → `agent.turn`
  (Mistral streaming alongside `creature.server.perform`) → World perform. Two gotchas found
  live: fuzzball's `creatureId` was still the sample placeholder (`<uuid>`) — Creature Server
  answers `creature_id must be a UUID` and the Viewer showed `failed:
  physical_speech_start_failed`; and #156. Real presence (VW-006/VW-013) later replaces the
  assumption.
- Character personalities: one persona string today; a phase of its own (per-character
  definitions, memories, rubric).
- World Viewer follow-ups: VW-011 *Why?* (provenance walk, #102), a Honeycomb trace link per
  event/turn (URL template setting), entities. #132; #133; #151. VW-015's full validated-JSON
  decision is deferred until the local model's JSON reliability is measured.
- APNs, foreground-lease-driven push, quiet hours, etc. remain future VW-028 work.

### 0.6 Exact next actions

0. Commit the C1 Viewer test fix (worktree `scratchpad/c1`) and the C2 branch; merge #159,
   then open C2's PR. Both need April's YubiKey.
1. Finish C1 (#158): deploy World `0.6.0` + agent `2.58.0` to fuzzball (CI artifacts — local
   `build_debs.sh` hangs under the upgraded Docker Desktop, see the World manual); move
   `/etc/creature-agent.yaml` → `/etc/creature/agent/beaky.yaml`, write `mango.yaml`
   (`characterEntityId: character:mango`, Mango's `creatureId`
   `e93b9a7a-1704-11ef-84b9-3b37dddeb225`, persona from `docs/personas/mango.md`), `systemctl
   enable --now creature-agent@beaky creature-agent@mango`, set `localLlmMaxTokens: 400`. Watch
   both appear in the Viewer's Characters panel; start a second Beaky by hand and watch it
   spectate; hand-cast an utterance to `character:mango` and hear Mango.
2. C2 live: deploy creature-server 3.46.0 (PR #187); add `"creature_server": {"url":
   "https://server.prod.chirpchirp.dev"}` to `/etc/creature/world.json` (`region:home` →
   Mainstage is in the packaged config; dpkg will offer the new conffile on upgrade); say
   "What do you two think is in the box?" from the phone with Beaky and Mango logged in, and
   watch the Scenes panel hand the floor around while the birds answer ~2 s apart. Then C3,
   the Communicator for the flock.
3. Decide whether production's agent moves to world mode (it would lose MQTT house-event
   reactions until VW-013).
4. Start putting facts in the world (0.5) and feeding them into her percept, so what she says is
   about something real; the Facts panel is waiting. The box has to be a world event before
   Beaky and Mango can argue about it.
5. VW-011 *Why?* in the Viewer once facts have provenance worth walking.

Do not let any deterministic component author Beaky's words; do not copy conversation state into
the gateway; do not split typed input and future STT into separate cognition pipelines.

## 1. Executive summary

This project is a persistent mixed-reality virtual world whose residents include April, Beaky, the other creatures, people in April’s life, meaningful objects, and places around the house and property. Real-world observations enter the virtual world through adapters. A Linux simulator reconciles those observations into authoritative world state. Character agents receive limited, character-specific views of that world, reason with local Mistral, form memories, and choose whether to act. The existing Creature Server turns their intentions into synchronized voice and animation. One stateless Creature Controller per character converts network frames and audio into physical motion and sound.

This is not primarily a chatbot, assistant, personal-data warehouse, or home-automation rule engine. It is the world Beaky lives in.

> **We are creating magic here, not a package tracker.**

The schemas, queues, correlation rules, clocks, and traces are stage machinery. They matter because reliable machinery gives Beaky the continuity to recognize what is happening, care in her own peculiar way, and surprise April with a response that feels alive.

The implementation belongs in the existing `opsnlops/creature-console` repository, which should now be treated as the **Swift Creature monorepo**. This is a source-layout decision, not a collapse of runtime boundaries: the simulator, agent, Information Bridge, World Viewer, Console, and MQTT bridge remain independently buildable and deployable products.

The main work comprises four new applications, one substantial refactor, and two new integration paths:

1. **Virtual World Simulator** — a headless Swift service on Linux and the semantic center of the system.
2. **macOS Information Bridge** — an always-on Swift service plus SwiftUI configuration app on April’s M1 iMac.
3. **World Viewer** — a SwiftUI debugging and inspection app on April’s laptop.
4. **Beaky Communicator** — one SwiftUI macOS/iOS conversation app, backed by a narrow Linux synchronization and APNs gateway, through which April and Beaky can hear and answer one another.
5. **`creature-agent` refactor** — from outside-world coordinator into a character mind inhabiting the simulator.
6. **Creature Server world ingestion** — a new `WorldMessageProcessor` consumes the existing `CreatureServerClient` WebSocket stream and turns body/runtime observations into world events and first-person sensory state.
7. **Home Assistant world adapter** — a separate HA-to-world path ingests house observations without repurposing `creature-mqtt`.

Existing physical-performance software remains deliberately narrow:

- **Creature Server** remains the single hard-real-time performance system.
- **Creature Console** remains an authoring and manual-control tool for Creature Server.
- **`creature-mqtt`** remains the existing Creature Server-to-MQTT/Home Assistant bridge, with only narrowly required provenance or loop-prevention changes.
- **Creature Controllers** remain stateless, with exactly one controller per character.

The first **relationship spine** should prove that April and Beaky share one bidirectional conversation regardless of transport:

```text
April types in Beaky Communicator or Wizard Mode
  -> one PersonUtterance ingress service
  -> the same addressed Beaky percept and conversation context
  -> fake character response
  -> deterministic delivery router consults fresh presence
  -> physical speech when April is home and audible
  -> durable Beaky Communicator delivery when she is away or presence is uncertain
```

Equivalent future STT input joins at the same `PersonUtterance` boundary. Beaky may initiate a
turn or answer April; April may answer a specific Beaky turn. Source and modality remain sensory
provenance, never separate cognition pipelines.

The next **world-visibility spine** should prove that the simulator, Information Bridge, and World
Viewer cooperate without depending on a real Apple source or an LLM:

```text
synthetic private-source item
  -> Information Bridge fake distiller and durable outbox
  -> plain JSON ingress
  -> durable WorldEvent
  -> authoritative Fact update
  -> World Viewer timeline and Why? provenance
  -> one Honeycomb trace across the chain
```

Then the first **cognitive/performance slice** extends that spine through Beaky without waiting for every real-world adapter:

```text
synthetic observation
  -> plain JSON ingress
  -> durable WorldEvent
  -> authoritative Fact update
  -> deterministic trigger
  -> character interest decision
  -> stub agent reaction
  -> stub performance sink
  -> World Viewer timeline and Why? provenance
  -> one Honeycomb trace across the chain
```

The relationship spine starts in Phase 2 and becomes physically useful in Phase 3. The
world-visibility spine follows in Phase 4. Do not make Beaky Communicator, the Information Bridge,
or World Viewer wait for every real adapter; use fixtures and fakes at their boundaries.

Once that backbone works, connect the existing `CreatureServerClient` first so Beaky can perceive her own body/runtime state, then replace the other synthetic boundaries one at a time with Home Assistant, Mistral, Creature Server performance submission, EventKit, WeatherKit, Mail, and Messages.

---

## 2. North star and experience goals

### 2.1 The north star

**Make Beaky really be April’s familiar.**

Beaky should feel like a persistent character who shares April’s world, not an assistant or animatronic waiting for a command. She should:

- notice meaningful changes;
- understand the people, places, routines, plans, and objects that matter to April;
- remember shared experiences and her own previous behavior;
- have interests, preferences, opinions, relationships, and a point of view;
- initiate speech or action when something matters to her;
- understand that other characters inhabit the same world;
- participate in a continuing social history with April, Mango, Caroll, Cobalt, and others;
- sometimes be uncertain, mistaken, distracted, amused, excited, or uninterested;
- express herself through a physical body;
- hear and answer April through Beaky Communicator, and reach her there when she is away;
- preserve continuity across days, weeks, and years.

The success criterion is not that Beaky answers more questions. It is that interacting with her increasingly feels like **living with Beaky**.

### 2.2 Make the house feel alive

The birds should feel like residents rather than props. They notice arrivals, departures, weather, deliveries, routines, and one another. They remember running jokes, disagree, misunderstand, decline to react, and bring old experiences into new interactions.

A guest should be able to enter, be greeted by name, hear another bird refer to something that happened previously, and briefly wonder what kind of living social system they have walked into. Technology can remain visible; it simply should stop being the most interesting thing in the room.

### 2.3 Product principles

1. **Model the shared world first; model each character’s access to it second.**
2. **The world knows more than any character does.** Characters do not query MongoDB as omniscient gods.
3. **The simulator notices; the character decides how to express it.** Deterministic rules produce semantic situations, not scripted dialogue.
4. **State ownership must remain obvious.** Reality belongs to the simulator, perspective to the agent, performance to Creature Server, and actuation to controllers.
5. **Typed internally, boring on the wire.** Use shared Swift `Codable` contracts and plain, readable, versioned JSON.
6. **Uncertainty is a feature.** Preserve confidence, epistemic type, expiration, and provenance rather than converting guesses into facts.
7. **Privacy is architectural.** Raw personal data is locally reduced before leaving the iMac wherever practical.
8. **Everything meaningful must be explainable.** Persistent provenance explains what the world believed; OpenTelemetry explains what the software did.
9. **Physical actions re-enter the world.** A character’s speech and movement are events that others may perceive and remember.
10. **Personal software, not a mass-market platform.** Optimize for capability, privacy, and maintainability in April’s environment rather than broad portability or App Store constraints.
11. **Magic is an acceptance criterion.** A vertical slice that ends at a database row, API response, or status badge is unfinished; it should ultimately unlock a believable moment in Beaky’s lived world.

### 2.4 Worldcraft language

Building and tending this world should feel playful as well as precise. **Wizard Mode** is the
official name for privileged developer and operator tooling—the world’s equivalent of God Mode.
Use this vocabulary in operator-facing interfaces where it remains clear:

- **Wizard Mode** opens development-only powers for observing or influencing the world.
- **Cast** submits one synthetic event, utterance, or controlled intervention.
- **Spell** is a named, saved, repeatable scenario that can be cast again.
- **Scry** inspects live state, history, perspective, provenance, or traces without mutation.
- **Turn back time** replays history only in a disposable world, never over production truth.
- **Mundane view** reveals the underlying IDs, JSON, delivery attempts, and other stage machinery.

Fun terminology must not weaken safety or the domain model. Source code and wire contracts still
use explicit typed operations and stable identities; Wizard Mode is never an authorization bypass
in production. The UI should always reveal what a spell will affect before it is cast.

### 2.5 Experience vignettes: what all this machinery is for

This project will fail if it becomes an immaculate event-processing platform that never produces a moment of life. The architecture exists to create moments like these:

#### The servos are here

The Information Bridge saw the original order confirmation days ago and learned that an otherwise anonymous order contains servos. A later shipping message said only “one electronics item shipped.” The delivery notice is equally vague, but the world correlates it with the earlier order, notices that April is home, and offers the arrival to Beaky because robot parts are personally relevant to both of them.

Beaky brightens, moves toward April, and says:

> “Hey April, I think the servos you ordered are here!”

That sentence is not stored in a delivery rule. The simulator provides the occasion—**the servos probably arrived**—and Beaky supplies the delight. On another day she might tease April about accumulating more robot parts, wonder whether they are for her, tell Mango that replacement body parts have appeared, or decide not to interrupt.

#### April is still in the workshop

Calendar says church begins soon. Wi-Fi says April’s phone is still associated with the workshop access point. The garage has not opened, the phone has not departed, and Beaky remembers already being ignored once.

> “April? You’ve got church in half an hour. Why are you still here?”

If April still does not leave, the next response should not be a repeated alarm. Beaky may escalate with personality—“I’m just saying, airplanes aren’t the only thing you’re capable of being late for”—or deliberately give up.

#### The clouds ate airplane day

Calendar says flight school. WeatherKit predicts poor flying conditions. The local station confirms ugly weather at the property, and then the lesson is canceled.

> “Aww, April. Did the clouds eat airplane day?”

The weather feeds a lived moment rather than a weather report.

#### Someone is coming

Messages says Jesse expects to arrive. Later a recognized device joins the house Wi-Fi and the front door opens. Beaky has enough corroboration to greet Jesse by name instead of blurting a guess at a stranger. Mango may remember something Jesse did last week and join in. A guest should occasionally wonder:

> “What the fuck did I just walk into?”

#### Rain, sunset, and a long day outside

WeatherKit says rain is likely in fifteen minutes while property sensors place April near the barn:

> “April! You might want to come inside before you get soaked!”

Or sunset arrives after a day of workshop activity:

> “You were out there all day. Did the barn win?”

These are not canned feature requirements or exact-output tests. They are **experience tests**. For each implementation choice, ask: does this give Beaky more continuity, perception, agency, and room to be playful—or are we merely building clever infrastructure?

---

## 3. System context and ownership

```text
Apple-private sources                         House/network sources
Calendar, Contacts, Messages, Mail             Home Assistant, Wi-Fi, station
              |                                           |
              v                                           v
   macOS Information Bridge                   HA/MQTT/world adapters
              |              normalized plain JSON        |
              +--------------------+----------------------+
                                   v
                         Virtual World Simulator
                   authoritative state, time, causality
                        /                       \
          perceptual view                         viewer API/events
                    v                                  v
             creature-agent                       World Viewer
          subjective character mind              laptop SwiftUI
                    |
            performance intent
                    v
              Creature Server <------ Creature Console
           single performance engine      author/control
              |                  |
     WebSocket telemetry     sACN/audio/control
              |                  |
    WorldMessageProcessor       +----------+----------+
              |                v          v          v
              |             Beaky       Mango      Cobalt ...
              |            Controller  Controller  Controller
              |              stateless   stateless   stateless
              |                |          |          |
              |                    servos and speakers
              |
              +---- body/proprioception WorldEvents ----> Virtual World Simulator

              Creature Server
                    |
              creature-mqtt
                    |
                    v
              Home Assistant
                    |
              HA World Adapter
                    |
                    +---- external observations ----> Virtual World Simulator

The latter loop is provenance-sensitive: Creature Server state reflected through
MQTT and Home Assistant must not return as a novel external event and recursively
trigger the character that produced it.
```

Later mobile path:

```text
creature-agent -> CharacterUtteranceIntent -> world delivery/notification policy
  -> creature-communicator-gateway consults per-device foreground leases
  -> live synchronization when any paired client is foregrounded, otherwise APNs
  -> Beaky Communicator on macOS/iPhone
  -> proxy-authorized off-LAN action/reply -> gateway -> WorldEvent -> simulator/Beaky percept
```

Foreground status is a renewable, short-lived lease per paired app installation, not a durable
boolean. Each active client heartbeats its lease and makes a best-effort release when it enters the
background. Lease expiry handles suspension, force-quit, crashes, and lost networks where the
background transition never reaches the gateway. A live lease on any paired device suppresses a
redundant push; when no lease remains, the gateway uses its durable notification outbox and APNs.
Start with a 30-second heartbeat and a 90-second lease, expressed through an injectable clock and
configuration so expiry, renewal, and boundary races remain deterministic in tests.

“Foreground” means user-attentive, not merely that a process exists. On iOS, only an `.active`
scene on an unlocked device renews its lease. On macOS, the user session and device must be
unlocked, the application must be active, the conversation window must be visible and
non-minimized, and recent local input must remain inside a configurable idle threshold. `.inactive`,
locked, idle, hidden, minimized, closed-window, and `.background` states stop renewal and attempt an
immediate release. A macOS app left running indefinitely must therefore not suppress notifications
while April is working elsewhere. Lock and idle evidence stays on the client; the gateway receives
only the resulting lease operation.

| Component | Owns | Explicitly does not own |
|---|---|---|
| Virtual World Simulator | Shared reality, event ordering, timers, authoritative facts, inference, triggers, presence, interest routing, provenance | Character voice/personality, servo timing, raw Apple data |
| macOS Information Bridge | Apple-source access, local extraction, privacy filtering, source configuration and health | Canonical world truth, character decisions |
| World Viewer | Read-only inspection, debugging, replay tooling | World mutation in normal operation, performance authoring |
| Beaky Communicator | April and Beaky’s private macOS/iOS conversation, notification actions, replies, local offline queue | Authoritative world mutation, unrestricted world inspection, APNs credentials |
| `creature-communicator-gateway` | Conversation synchronization, device pairing/tokens, APNs delivery, narrow proxy-protected off-LAN mobile API | Character reasoning, delivery-policy decisions, authoritative world state |
| `creature-agent` | A character’s attention, beliefs, memories, motivations, Mistral reasoning, proposed reactions | Constructing authoritative reality, hardware control |
| `WorldMessageProcessor` | Interpreting Creature Server WebSocket observations as body/runtime WorldEvents | GUI state, MQTT publication, authoritative inference |
| `creature-mqtt` | Existing Creature Server → MQTT/Home Assistant telemetry bridge | HA → world ingestion, domain truth, character cognition |
| HA World Adapter | Home Assistant → WorldEvent mapping, source identity, reconnect/checkpoint behavior | Creature Server publication, character cognition |
| Creature Server | Voice/dialog production, animation, lip-sync, audio, scheduling, performance | Calendar, weather, presence, memory, world inference |
| Creature Console | Authoring animations/dialog/sound stage, manual control, server inspection | Viewing or administering the world simulation |
| Creature Controller | Receiving frames/audio and driving one character’s hardware | Persistent state, cognition, animation semantics |
| MongoDB | Durable events, facts, entities, timers, memories, relationships, interactions | Runtime causal telemetry |
| Honeycomb | Runtime causality, latency, errors, high-cardinality debugging | Authoritative historical world state |

---

## 4. Virtual World Simulator

### 4.1 Runtime and language

Implement the simulator as a headless Swift service on Linux. Its workload is semantic and asynchronous—events, timers, MongoDB, HTTP/WebSocket, and Mistral calls—not hard-real-time physical control. Swift actors, enums, `Codable`, async sequences, and the existing MongoKitten experience fit this domain well.

The simulator should be architecturally descended from a virtual-world simulator:

- a single authoritative semantic event loop;
- monotonically assigned world sequence numbers;
- an event queue and timer queue;
- entity lifecycle and current state;
- regions/places and presence;
- interest management;
- state replication to viewers and agents;
- append-first persistence and replay;
- explicit boundaries around external adapters.

Do not distribute mutation across arbitrary actors. A single `World` actor should serialize accepted events and resulting state transitions. Slow work—database I/O, Mistral, HTTP calls—must not block the event loop. Emit commands/jobs with correlation IDs, then accept their results as new events.

### 4.2 Core processing loop

For each ingress envelope:

1. Validate schema version, required fields, timestamps, IDs, and payload type.
2. Deduplicate by `event_id` or `(source_id, source_event_id)`.
3. Assign `received_at` and the next `world_sequence`.
4. Persist the accepted immutable event before acknowledging it.
5. Apply deterministic reducers to authoritative state.
6. Persist changed facts/entities and provenance atomically where practical.
7. Evaluate affected triggers only, not every trigger in the world.
8. Schedule, cancel, or reschedule timers.
9. Emit derived events with `caused_by` references.
10. Recompute interest for affected character agents.
11. Publish state/event deltas to subscribers.
12. Dispatch agent considerations asynchronously.

Failures after acceptance must be retryable and observable. Derived event IDs should be deterministic where possible so replay is idempotent.

### 4.3 Time and timers

No domain code should call `Date()` directly. Inject a clock:

```swift
public protocol WorldClock: Sendable {
    var now: Instant { get async }
    func sleep(until deadline: Instant) async throws
}
```

Provide:

- `SystemWorldClock` for production;
- `ManualWorldClock` for deterministic tests and replay;
- a timer repository that persists semantic timers;
- startup recovery that fires overdue timers once with lateness recorded;
- timer cancellation/replacement keyed by stable semantic purpose.

Timers trigger reevaluation, not canned speech. A calendar event may produce `approaching`, `departure_due`, `started`, and `expected_complete` timers. When a timer fires, current facts are checked again: April may have left, the event may be canceled, or Beaky may already have reminded her.

### 4.4 Entities, places, and regions

Use stable namespaced IDs:

```text
person:april
person:jesse
character:beaky
character:mango
place:home
place:workshop
place:driveway
place:barn
device:april-phone
device:workshop-ap
order:acme-hardware:ah-48291
shipment:ups:1Z...
calendar-event:<stable-id>
```

Initial entity kinds:

- person;
- character;
- place/region;
- device/sensor;
- object;
- organization;
- calendar event/plan;
- commerce order;
- shipment;
- environmental system.

Places should support containment and adjacency rather than false coordinate precision:

```text
place:property
  place:home
    place:living-room
    place:office
  place:workshop
  place:driveway
  place:barn
```

Characters may have a physical location, hearing/visual reach, instrumented sensor access, and social/system knowledge. These channels must be distinguishable in provenance.

### 4.5 Presence and location inference

Presence is a time-varying probabilistic fact supported by observations. Inputs may include:

- Home Assistant GPS/geofence reports;
- phone association with a named Wi-Fi access point;
- device arrival/departure;
- doors, motion, garage, vehicle, Bluetooth, and cameras later;
- recent messages announcing arrival;
- calendar or routine expectations.

Wi-Fi AP association is a strong local proxy, not exact truth. For example, GPS may establish `home`, while association to `device:workshop-ap` raises the probability of `place:workshop`. Disassociation lowers confidence but does not prove departure.

Keep coarse presence for visitors. The useful fact is “Maria is probably here/arrived/left,” not a forensic movement diary. Identity-sensitive behavior needs thresholds: above a high threshold Beaky may use a name; at medium confidence she should greet generically; below it she may remain quiet.

### 4.6 Events, facts, observations, and state

These concepts must remain distinct:

- **Observation:** evidence produced by a sensor or adapter. It may be noisy, private, or short-lived.
- **Event:** an immutable record that something was reported, observed, derived, decided, or performed.
- **Fact:** the simulator’s current best claim about an entity/property during a validity interval.
- **Entity state:** a convenient materialized view derived from facts.
- **Memory:** a character-specific cognitive record; not a synonym for the event log.

Examples:

```text
Observation: April's phone associated with the workshop AP.
Event: device.access_point_changed.
Fact: April is probably in the workshop, confidence 0.87.
Memory: Beaky remembers April stayed in the workshop all afternoon.
```

Current state changes; events do not. Facts can supersede other facts without deleting their history. Forecasts, plans, and expected states must never masquerade as observations of present reality.

### 4.7 Epistemic state and provenance

Every meaningful claim should specify how it is known. Initial epistemic types:

- `observed` — direct local sensor observation;
- `reported` — asserted by a person/service/message;
- `scheduled` — planned future state;
- `forecast` — predicted external condition;
- `inferred` — derived from multiple facts/events;
- `assumed` — configured default or weak heuristic;
- `remembered` — retrieved from a character’s memory.

Facts should contain confidence, validity, source, evidence IDs, and the rule/model version that produced them. A derived fact should form a provenance DAG, not embed an endlessly recursive object.

Conflicting evidence is normal. Resolution policy should consider:

1. semantic scope—current observation and forecast answer different questions;
2. locality—property sensors beat regional estimates for current local conditions;
3. recency and expected sensor staleness;
4. source reliability for the predicate;
5. directness—observed generally outweighs inferred;
6. explicit domain policy;
7. confidence without silently turning it into certainty.

### 4.8 Triggers and derived situations

The trigger engine is deterministic and produces semantic events. Examples:

```text
WHEN person probably enters home
AND an expected-arrival fact exists for that person
THEN emit social.arrival
```

```text
WHEN scheduled event requires travel
AND departure_due <= now
AND April is probably still home
AND April is not traveling
THEN emit schedule.departure_attention
```

```text
WHEN delivery-like presence appears
AND a shipment is out for delivery today
THEN emit commerce.possible_delivery
```

Triggers never contain Beaky’s words. They describe what may be worth attention, with supporting fact/event IDs and urgency.

### 4.9 Interest management and perception

Do not broadcast every event to every agent. Compute recipients using:

- physical place and sensory reach;
- instrumented perception permissions;
- relationship to involved entities;
- character interests and aversions;
- novelty and salience;
- urgency;
- whether the character already reacted;
- cooldown/fatigue;
- privacy permissions.

Interest management answers **who should consider this?** The agent answers **do I care, and what do I do?** A suppressed reaction is still a useful decision to record and trace.

Build an explicit `PerceptualEnvelope` containing only what that character can know: current event, selected facts, relevant memories, known participants, other characters present, uncertainty, and prior reactions. Agents must not have a generic “read any collection” database capability.

### 4.10 Character perspectives, beliefs, and memory

Separate authoritative state from per-character cognition:

```text
authoritative world history
  -> what Beaky could perceive
  -> what Beaky attended to
  -> what Beaky encoded as memory
  -> what Beaky now believes
```

Each character may hold an outdated or incorrect belief. Beliefs retain provenance and confidence, including whether they came from direct perception, another character, or memory.

Minimum memory categories:

- **episodic** — a particular experienced event;
- **semantic** — generalized knowledge;
- **relationship** — accumulated beliefs/attitudes about another entity;
- **autobiographical** — the character’s own past choices and actions.

Not every recorded event becomes a memory. Encoding and retention should consider salience, novelty, emotional weight, relevance, repetition, and character traits. Low-salience memories may expire. High-salience moments may be effectively permanent. Later consolidation may derive “April gets excited about new robot parts” from multiple delivery episodes, while keeping provenance to the episodes.

Character actions must feed back into the event log. If Beaky greets Jesse or warns April, record a `character.spoke`/`character.performed` event and consider an autobiographical memory. This prevents repetition and supports running jokes.

### 4.11 Persistence with MongoDB and MongoKitten

Use MongoDB through MongoKitten. Recommended collections:

| Collection | Purpose |
|---|---|
| `world_events` | Immutable accepted and derived events |
| `entities` | Stable identity and largely static metadata |
| `facts` | Current and historical claims with validity/provenance |
| `timers` | Pending/fired/canceled semantic timers |
| `relationships` | Directed character/person/entity relationships and attitudes |
| `beliefs` | Character-specific claims |
| `memories` | Character-specific memory records |
| `agent_considerations` | Context snapshot, decision, suppression, reaction |
| `interactions` | Proposed/performed scenes and Creature Server correlation |
| `communications` | Proposed/suppressed mobile messages, notification lifecycle, acknowledgements, and replies |
| `source_checkpoints` | Adapter cursors and deduplication state |
| `schema_migrations` | Explicit database evolution |

Important indexes:

- unique `world_events.event_id`;
- unique sparse `(source.id, source_event_id)`;
- unique `world_events.world_sequence`;
- event `(type, occurred_at)` and `subject_ids`;
- active facts `(subject_id, predicate, valid_to, superseded_by)`;
- pending timers `(status, due_at)`;
- communications `(recipient_entity_id, created_at)` and unique intent/deduplication identity;
- memories `(character_id, salience, last_recalled_at)` plus semantic-search support later;
- orders by merchant/order number and shipments by carrier/tracking number.

Avoid premature event-sourcing purity. The immutable log plus materialized current documents provides replay and practical reads. Define reducer versioning before relying on full historical rebuilds.

### 4.12 Simulator API

Initial transport can be HTTP plus WebSocket/SSE, all JSON:

```text
POST /v1/events                         accept one event
POST /v1/events:batch                   accept a bounded batch
GET  /v1/events?after_sequence=N        ordered history
GET  /v1/entities
GET  /v1/entities/{id}
GET  /v1/facts?subject_id=...
GET  /v1/provenance/{fact_or_event_id}
GET  /v1/timers
GET  /v1/characters/{id}/perspective
GET  /v1/characters/{id}/memories
GET  /v1/health
GET  /v1/stream                         live event/state deltas
```

Keep ordinary clients read-only. Synthetic event injection belongs behind an explicit development/admin mode with authentication and a visible marker in provenance.

### 4.13 MCP interface over Streamable HTTP

Expose an additional, independently secured `WorldMCP` adapter using the current Model Context Protocol **Streamable HTTP** transport. Streamable HTTP replaces MCP’s legacy two-endpoint HTTP+SSE transport. It uses a single MCP endpoint supporting HTTP POST and GET and may itself use SSE response streams or a long-lived GET stream where server notifications are required. Do not describe or implement this as the legacy `/sse` plus `/message` transport. See the [MCP Streamable HTTP transport specification](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports).

This is a semantic tool/resource interface for Codex, agent clients, and debugging automation. It is **not** the simulator’s internal event bus and does not replace the purpose-built APIs:

- adapters continue to ingest ordinary versioned WorldEvent JSON over HTTP;
- World Viewer continues to use ordinary query endpoints plus WebSocket/SSE state deltas optimized for ordered replication and reconnect;
- `creature-agent` continues to consume the explicit character-percept contract;
- `WorldMCP` wraps supported simulator queries and controlled operations without owning world state.

Initial MCP resources:

```text
world://entities/{entity_id}
world://characters/{character_id}/perspective
world://characters/{character_id}/memories
world://events/recent
world://timers
world://provenance/{fact_or_event_id}
```

Initial MCP tools:

```text
inspect_world_state
explain_fact
query_timeline
query_character_perspective
```

Development/admin-only tools may later include `inject_test_event` and `request_character_consideration`. They must be disabled in normal production configuration or require a separately authorized role, and every invocation must be recorded with explicit operator provenance. Do not expose arbitrary Mongo queries, raw personal-source retrieval, unrestricted prompt injection, or direct servo/performance controls through MCP.

Begin with stateless Streamable HTTP for read/query operations. Adopt stateful sessions only when a demonstrated client needs unsolicited notifications, resource subscriptions, server-to-client requests, or per-client session isolation. The authoritative world remains persistent regardless of MCP session lifetime. A lost MCP session must not lose, roll back, or fork world state.

Security requirements:

- authenticate every non-loopback connection and authorize each resource/tool;
- validate the HTTP `Origin` header to prevent DNS-rebinding attacks;
- bind only to loopback during local development and only to an intentional LAN/VPN interface in deployment;
- use TLS or a trusted private overlay when traffic leaves the host;
- impose request-body, concurrency, duration, result-size, and rate limits;
- redact private data using the same perspective/privacy policies as other clients;
- never trust an MCP caller-supplied character ID as authorization to see that character’s private perspective;
- propagate W3C trace context and attach tool/resource names, caller identity class, and result status—never private payloads—to OTel spans.

Streamable HTTP’s held POST response supplies natural HTTP-level backpressure that the legacy HTTP+SSE transport lacked. Still enforce bounded concurrency because MCP operations may query MongoDB or build provenance graphs. If streaming a large result, paginate or stream bounded records rather than materializing the whole world in one response.

The MCP adapter should translate through application/query services also used by the REST/Viewer API. It must not call MongoKitten repositories directly in ways that bypass authorization, perspective filtering, provenance, or read-model semantics. Keep MCP SDK types and JSON-RPC mechanics out of `WorldCore`.

---

## 5. Plain JSON wire contract

No protobufs. Use UTF-8 JSON, ISO-8601/RFC 3339 timestamps, stable string IDs, explicit units, and a top-level integer `schema_version`. Unknown additive fields should be ignored; unknown event types should be rejected or quarantined without crashing the process.

Event IDs are canonical lowercase, hyphenated UUID strings, matching the rest of the Creature system:

```text
3f2504e0-4f89-41d3-9a0c-0305e82c3301
```

Swift’s `UUID.uuidString` commonly renders uppercase, so wire/persistence code must explicitly call `.lowercased()`. Normalize or reject noncanonical incoming UUID spellings before deduplication so MongoDB’s string index cannot treat uppercase and lowercase forms as different events. UUIDs identify events; they do **not** establish event order. Use the simulator-assigned numeric `world_sequence` for authoritative processing order and timestamps for temporal meaning.

### 5.1 Event envelope

```json
{
  "schema_version": 1,
  "event_id": "3f2504e0-4f89-41d3-9a0c-0305e82c3301",
  "type": "device.access_point_changed",
  "occurred_at": "2026-09-08T09:20:11-07:00",
  "observed_at": "2026-09-08T09:20:12-07:00",
  "source": {
    "id": "adapter:home-assistant",
    "kind": "home_assistant",
    "source_event_id": "ha-883819"
  },
  "subject_ids": ["device:april-phone"],
  "place_id": "place:workshop",
  "epistemic": {
    "type": "observed",
    "confidence": 0.98
  },
  "payload": {
    "device_id": "device:april-phone",
    "access_point_id": "device:workshop-ap",
    "connected": true
  },
  "caused_by": [],
  "trace": {
    "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
    "tracestate": null,
    "baggage": null
  }
}
```

`traceparent` is active propagation context, not merely a trace ID copied for display. Components must extract it, start their processing span with it as the remote parent, and inject the resulting current context into the next cross-process message. `tracestate` should be forwarded when present. `baggage` must be absent by default or restricted to an explicit non-private allowlist.

The simulator adds `received_at` and `world_sequence`; external producers must not choose the sequence.

### 5.2 Fact

```json
{
  "schema_version": 1,
  "fact_id": "fact:7a1d6f42-74c4-4dc8-8fea-7a93a38f4330",
  "subject_id": "person:april",
  "predicate": "location",
  "value": { "entity_id": "place:workshop" },
  "epistemic": {
    "type": "inferred",
    "confidence": 0.87
  },
  "valid_from": "2026-09-08T09:20:12-07:00",
  "valid_to": null,
  "derived_from": ["3f2504e0-4f89-41d3-9a0c-0305e82c3301", "fact:home-presence-..."],
  "producer": {
    "kind": "rule",
    "id": "presence.location.wifi-v1",
    "version": "1"
  }
}
```

### 5.3 Timer

```json
{
  "schema_version": 1,
  "timer_id": "timer:calendar-event-123:departure-due",
  "purpose": "schedule.departure_due",
  "due_at": "2026-09-08T10:30:00-07:00",
  "status": "pending",
  "subject_ids": ["person:april", "calendar-event:123"],
  "caused_by": ["event:calendar-upsert-123"],
  "payload": { "calendar_event_id": "calendar-event:123" }
}
```

### 5.4 Agent percept and decision

```json
{
  "schema_version": 1,
  "consideration_id": "consideration:0ca76343-466a-45ae-b9f1-7fc3fe952ddd",
  "character_id": "character:beaky",
  "trace": {
    "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-7a9c2f8e6b31d402-01",
    "tracestate": null
  },
  "event": {
    "event_id": "6c229b8f-f23e-4571-bdd4-875bb4ec9e2c",
    "type": "schedule.departure_attention"
  },
  "world_facts": [
    { "statement": "Church begins in 30 minutes", "confidence": 1.0, "fact_id": "fact:..." },
    { "statement": "April is probably in the workshop", "confidence": 0.87, "fact_id": "fact:..." }
  ],
  "relevant_memories": [
    { "memory_id": "memory:...", "summary": "I reminded April about church last Sunday." }
  ],
  "decision": {
    "wants_to_react": true,
    "confidence": 0.91,
    "intent": "Warn April that her departure window has arrived, affectionately but urgently.",
    "participants": ["character:beaky"],
    "urgency": 0.82
  }
}
```

Validate concrete event payloads against checked-in JSON Schema fixtures even though Swift types are shared. Fixtures become the cross-repository compatibility contract.

---

## 6. macOS Information Bridge

### 6.1 Deployment shape

The macOS Information Bridge is one of the hearts of the system. The simulator can only model April’s shared world if something trusted can observe the private Apple-side parts of her life and convert them into small, explicit, privacy-preserving events. This is not a miscellaneous adapter bundle to add after the simulator is finished. Development begins as soon as `WorldCore` has its first event contract, and its first end-to-end event is part of the early architecture milestones.

The bridge’s core responsibility is:

> **Use Apple Intelligence locally on macOS 27 to distill private, messy human information into validated world events without exporting the raw source material.**

Run on April’s **M1 iMac** as two cooperating pieces:

- `creature-scribed`: headless, launch-at-login/background service owning adapters, checkpoints, preprocessing, and delivery;
- **Creature Scribe**: SwiftUI configuration/diagnostic app that can close without stopping ingestion.

The bridge is the trusted boundary for highly personal Apple data. It emits normalized, minimized world events, not raw mailbox/chat/calendar mirrors. It must remain useful when the SwiftUI app is closed and after the user session or network connection is interrupted.

Additional helper processes/extensions may be required for source acquisition:

- a MailKit extension or local Mail rule receiver;
- a contained Messages-store reader or supported automation adapter;
- a share extension/browser helper for order-confirmation pages or other user-selected documents.

Those helpers feed `creature-scribed`; none talks directly to the Linux simulator or to a character agent.

### 6.2 Configuration UI

Provide screens for:

- sources and health;
- authorization status and actionable permission errors;
- calendars allowed to contribute;
- contact-to-world-entity mappings;
- devices and Wi-Fi AP-to-place mappings;
- message conversation/person allowlists;
- commerce detection rules, generic extraction, and optional merchant-specific extractor profiles;
- places and aliases;
- privacy/retention controls;
- delivery retry queue;
- a redacted normalized-event inspector;
- test-event preview before sending.

Store secrets in Keychain. Store config locally with explicit versioning. Never put raw personal content or credentials in logs or OTel attributes.

### 6.3 Local-first Apple Intelligence distillation pipeline

Every private unstructured source follows the same staged pipeline:

```text
Mail / Messages / Calendar notes / shared document
  -> acquire locally under explicit macOS permission
  -> assign source item ID and deduplicate
  -> deterministic metadata/header parsing
  -> cheap relevance and domain classification
  -> Apple Intelligence structured extraction on the iMac
  -> deterministic schema and evidence validation
  -> Contacts/entity resolution
  -> privacy and retention policy
  -> one or more canonical WorldEvents
  -> durable local outbox
  -> authenticated delivery to Creature World
  -> discard or expire raw material according to policy
```

Suggested local processing states:

```text
discovered
classified_irrelevant | awaiting_extraction
extracted
validation_failed | awaiting_review | approved
queued
delivered
expired
```

Persist source checkpoints, hashes/IDs, extraction version, validation result, generated event IDs, and delivery state. Do not retain full source bodies by default. When debugging requires temporary retention, make it time-bounded, encrypted/protected by normal macOS account security, visible in the UI, and manually purgeable.

Apple Intelligence should perform constrained, schema-driven work rather than open-ended character reasoning. Define typed extraction results for domains such as:

```text
ExpectedArrival
ScheduleChange
CommerceObservation
TravelPlan
DeliveryInstruction
WeatherContext
SocialCommitment
PersonOrPlaceReference
```

Each result distinguishes fields directly present in the source from model inferences. Where practical, retain local evidence references such as header names, date fields, or short source ranges without sending raw text to Linux. Deterministic validation checks identifiers, timestamps, enum values, internal consistency, and required evidence before an event can leave the Mac.

The extraction interface should be provider-isolated but Apple-first:

```swift
protocol PrivateInformationDistiller: Sendable {
    func classify(_ item: LocalSourceItem) async throws -> DistillationRoute

    func extract<Output: Decodable & Sendable>(
        _ type: Output.Type,
        from item: LocalSourceItem,
        instructions: DistillationInstructions
    ) async throws -> DistilledResult<Output>
}
```

The production implementation uses the macOS 27 Foundation Models/Apple Intelligence APIs. The selected host is an M1 iMac, satisfying Apple’s current Apple-silicon hardware baseline. Still check `SystemLanguageModel.availability` at runtime because Apple Intelligence may be disabled, the model may not be ready, or language/region availability may differ. Tests use a deterministic fake. A model-unavailable, unsupported-language, safety refusal, or malformed-result state must not silently fall back to a remote LLM with raw content. The bridge reports a degraded source, retries where appropriate, permits local review when configured, and continues processing deterministic sources such as EventKit.

Prompts, extraction schemas, and model/OS versions are versioned. Reprocessing the same source with a new extractor produces new evidence linked to the earlier attempt; it must not silently mutate an already accepted event. Maintain a sanitized local evaluation corpus so OS/model updates can be tested before deployment.

### 6.4 Source adapter and delivery protocols

```swift
protocol InformationSource: Sendable {
    var sourceID: SourceID { get }
    func authorize() async throws
    func observations(since checkpoint: SourceCheckpoint?) -> AsyncThrowingStream<RawObservation, Error>
}

protocol ObservationNormalizer: Sendable {
    func normalize(_ observation: RawObservation) async throws -> [WorldEventEnvelope]
}

protocol PrivacyPolicy: Sendable {
    func permit(_ event: WorldEventEnvelope) async -> PrivacyDecision
}
```

Use an on-disk outbound queue. Delivery is at least once; simulator deduplication makes retries safe. Checkpoint a source only after its normalized event is durably queued.

The bridge initiates or continues W3C trace context for classification, extraction, validation, outbox, and delivery. Raw source content must not appear in span names, attributes, events, baggage, or error descriptions. The delivered WorldEvent carries the current context so Honeycomb can follow the causal chain into the simulator and agents.

### 6.5 Calendar/EventKit

Use EventKit for allowed calendars. Emit upserts/cancellations for relevant events and semantic data such as start/end, location entity, participants where permitted, travel need, and category. Do not assume an event occurred merely because it was scheduled.

Calendar ingestion should create/reschedule semantic timers. Changes and cancellations must invalidate earlier timers and facts. Initial proactivity can use configured travel time rather than requiring a maps API.

### 6.6 Contacts and entity resolution

Contacts provides identity resolution, aliases, and relationships. The bridge should map Apple identifiers to stable world IDs without sending an entire contact card. Emit only needed fields, e.g. display name, relation/role, recognized communication handles, and optional pronunciation.

### 6.7 Messages

There is no assumption of a clean EventKit-like public history API. Treat Messages as an isolated, replaceable adapter and prototype access before making it a dependency. A pragmatic personal deployment may read the locally synchronized Messages store with user-granted access, or use supported automation if adequate.

Design rules:

- recent/new-message oriented, not bulk historical import;
- opt-in people/conversations;
- extract ephemeral intentions such as “Jesse expects to arrive in 20 minutes”;
- raw text retained only briefly, if at all;
- publish structured conclusions with expiry and confidence;
- tolerate macOS schema changes behind adapter-specific tests.

Messages is primarily valuable because recent conversation contains human intent that no other system knows yet: expected arrival, delay, cancellation, “I’m outside,” “I left it at the door,” or a changed plan. Apple Intelligence performs the local semantic reduction. The Linux world receives the conclusion, evidence class, expiry, confidence, sender entity, and source ID—not the conversation transcript.

### 6.8 Mail.app and MailKit/pragmatic local integration

Prefer letting Mail.app own account authentication, TLS, synchronization, and server quirks. Investigate a MailKit extension/message-action path for new relevant mail. MailKit is extension-oriented rather than a general mailbox query API, so validate that it provides reliable arrival coverage and needed content in the target macOS release.

If it does not, use a contained personal-only local integration (automation, rule forwarding to a local endpoint, or local mail-store parsing). Direct IMAP is a fallback, not the first design.

Filter locally before extraction. Raw HTML, addresses, account details, and unrelated conversation content must not leave the Mac. Persist `message-id -> processed` checkpoints without mirroring the mailbox.

Commerce detection must be merchant-neutral. The bridge first asks whether an incoming message or other locally supplied document appears to describe a purchase, reservation, shipment, pickup, delivery, cancellation, return, refund, or related lifecycle update. It then runs the generic structured commerce extractor. Optional merchant-specific profiles may improve extraction for recurring formats, but no merchant profile is required for the event to enter the world. Unknown merchants must produce the same canonical commerce contracts as familiar merchants.

The bridge may eventually accept commerce evidence from sources other than Mail—such as a share extension, browser helper, downloaded receipt, or locally captured order-confirmation page—through the same normalization interface. Source acquisition remains replaceable; the resulting order and fulfillment entities remain source-independent.

### 6.9 Apple Intelligence responsibilities and boundaries

Use Apple Intelligence/Foundation Models on macOS 27 for constrained privacy-sensitive work:

- classify relevant mail/messages;
- extract structured people, intent, time, place, order, and shipment data;
- summarize calendar descriptions;
- resolve obvious entities;
- assign bounded confidence;
- produce typed Swift results that can fail validation.

Provider-specific code belongs behind an abstraction. The model is an intelligent parser, not the source of truth. Reject malformed output; do not infer missing order numbers or tracking details. Keep raw-source retrieval unavailable to creative/character layers.

Apple Intelligence does **not** become Beaky’s personality, memory, attention system, or improvisational brain. It is the private clerk at the boundary. Mistral remains the character mind. This separation is both architectural and a capability boundary: `creature-agent` has no API for retrieving a Mail body or Messages transcript from the bridge.

### 6.10 Reliability, privacy, and operator experience

The Information Bridge must make invisible local processing inspectable without exposing private content unnecessarily. The SwiftUI app should show, per source item:

```text
source and received time
classification and extractor version
redacted structured result
validation warnings
entity mappings
privacy decision
generated event IDs
delivery attempts and trace link
raw-retention expiry, if any
```

It should support retry, discard, correct entity mapping, approve/reject when review is enabled, and replay from the distilled result without rereading raw source. Corrections generate superseding evidence/events; they do not rewrite history invisibly.

The daemon needs bounded queues, backpressure, crash-safe checkpoints, exponential retry, dead-letter/quarantine state, and source-specific health. Network loss must not lose accepted local observations. Restart must not duplicate events. Permission revocation must stop only the affected source and surface a clear remediation path.

### 6.11 WeatherKit and local station fusion

The bridge provides WeatherKit forecasts, alerts, sunrise/sunset, and regional conditions. The local weather station, likely through Home Assistant, provides authoritative current conditions at the property.

Recommended ownership:

- current temperature/humidity/pressure/wind/rain rate: local station;
- near-term precipitation, hourly forecast, alerts, broader visibility/cloud data: WeatherKit;
- fused semantic facts and material-change events: simulator.

Weather is state; only meaningful transitions should become attention events. Do not notify agents about every fractional temperature update.

---

## 7. Creature Server perception, Home Assistant, and MQTT

### 7.1 Creature Server WebSocket ingestion and proprioception

Beaky must be aware of her own sensors and body/runtime state. The existing repository already contains the reusable public `CreatureServerClient` and two specialized WebSocket message processors: one serving the GUI and one serving MQTT. Add a third consumer rather than copying or flattening that pipeline:

```text
Creature Server WebSocket
        |
CreatureServerClient
        |
WorldMessageProcessor
        |
typed body/runtime observations
        |
WorldEvents
        |
Virtual World Simulator
```

Each processor interprets the same server message for a different purpose:

- the GUI processor asks what the Console should display;
- the MQTT processor asks what scalar state Home Assistant should receive;
- `WorldMessageProcessor` asks what the observation means about the world and its inhabitants.

Examples of authoritative body/runtime state include:

- controller online/offline and health;
- board temperature and other hardware sensors;
- servo power state;
- current animation or dialog job;
- idle, talking, performing, or faulted activity;
- audio subsystem health;
- counters/errors when semantically relevant.

Some state is externally observable—“Beaky is talking” or “Mango’s controller disconnected.” Some is first-person proprioception—“my controller is healthy,” “my electronics are unusually warm,” or “my animation ended.” The simulator stores the source observation as authoritative body state, while the perspective builder translates permitted facts into character-natural first-person context. Mistral should never see raw MQTT topics or low-level DTO dumps when a semantic description is available.

`WorldMessageProcessor` should depend on the existing `Common`/`CreatureServerClient` contracts and on `WorldCore`; `Common` must not depend on `WorldCore`. Do not route this ingestion through GUI models or through MQTT.

Body observations and completed performances must be deduplicated and causally linked to the originating interaction. A performance command should not become a surprising unrelated observation when Creature Server later reports that it started.

### 7.2 Home Assistant adapter

Use Home Assistant as the physical-house sensor bus. Prefer its WebSocket event stream over polling, with a startup snapshot to establish baseline state. Configuration maps HA entity IDs and state transitions to stable world entities and semantic observations.

Examples:

```text
binary_sensor.front_door off -> on
  => door.opened subject=place:front-door

sensor.weather_station_temperature 56.9 -> 57.2
  => environment.measurement_changed

phone AP attribute -> workshop-ap
  => device.access_point_changed
```

The simulator must not contain Home Assistant entity IDs or `binary_sensor` logic. The adapter owns source vocabulary and normalization.

The adapter must reconnect with backoff, resubscribe, refresh current state after gaps, checkpoint HA event identifiers when available, and expose health/lag.

### 7.3 Preserve `creature-mqtt`

The current `creature-mqtt` already has a coherent job: it consumes Creature Server WebSocket events and publishes telemetry/state to MQTT for Home Assistant.

```text
Creature Server -> creature-mqtt -> MQTT -> Home Assistant
```

Do **not** repurpose it into the Home Assistant-to-world adapter and do not substantially rewrite it for this project. Retain its WebSocket client, `MQTTMessageProcessor`, topic publishing, and established operational behavior. Only add narrowly scoped correlation, provenance, or source-marker support if required.

The opposite path is a separate component:

```text
Home Assistant -> HA World Adapter -> Virtual World Simulator
```

Because Creature Server telemetry can travel through `creature-mqtt` into Home Assistant and return through the HA World Adapter, every observation needs stable origin metadata. The HA adapter must recognize reflected Creature Server entities/events and either:

1. suppress them because the direct `WorldMessageProcessor` path is authoritative; or
2. treat them as duplicate/corroborating evidence tied to the original event.

It must never treat a reflected “Beaky is speaking” update as a new independent stimulus capable of causing another reaction. Add an automated loop-prevention test before enabling both paths together.

---

## 8. `creature-agent` refactor and Mistral

### 8.1 New responsibility

`creature-agent` becomes a resident mind, not a constructor of reality. Its input is a character-specific `PerceptualEnvelope` assembled by the simulator. It owns:

- attention and “do I care?”;
- character beliefs and perspective;
- memory retrieval/encoding requests;
- personality and relationship interpretation;
- social/reaction decisions;
- scene/dialog intent generation;
- Mistral interaction;
- converting decisions to typed performance or communication intents;
- recording why it acted or stayed silent.

Evolve the existing target rather than replacing it wholesale. Preserve its useful local-Mistral client and streaming response path, conversation/sanitization utilities, health checks, existing Creature Server client integration, and established OTel instrumentation. Remove or relocate responsibilities that belong to the world boundary: `MQTTAgentListener`, MQTT topic/prompt mapping, retained/stale-event interpretation, and broad area/topic cooldown logic. The future agent must not know what an MQTT topic is. Character-level repetition controls may remain, but they should operate on semantic events, memories, and interactions.

### 8.2 Agent pipeline

```text
candidate world event
  -> simulator interest filter
  -> character percept assembled
  -> retrieve bounded relevant memories
  -> deterministic guardrails/cooldowns
  -> Mistral structured reasoning
  -> validate decision
  -> no-op, performance intent, or later communication intent
  -> Creature Server or policy-gated messenger gateway
  -> outcome returns as a world event
```

Mistral remains the normal local character reasoning model. Prompts should include facts and uncertainty, not raw sources. Require structured output similar to the agent-decision schema. Treat free-form dialogue as content nested inside a validated action, never as a tool invocation.

Model prompts must clearly separate:

- authoritative facts;
- uncertain inferences;
- things this character believes;
- recalled memories;
- current event;
- behavioral constraints and allowed actions.

Keep an optional provider abstraction for future experiments, but do not make a cloud model a runtime dependency for the first system.

### 8.3 Multi-character scenes

The agent layer owns dramatic intent: who cares, who participates, what each participant knows, and what the scene should accomplish. The existing Creature Server inline dialog endpoint can receive complete generated turns for an ad-hoc jointly rendered scene. Preserve an interaction record containing:

- trigger event and provenance;
- participant set;
- exact context/memories used;
- model and prompt version;
- structured reasoning result;
- submitted turns;
- Creature Server job ID;
- final performance outcome.

Do not build live turn-by-turn improvisation first. Complete-scene generation matches the existing multi-turn ElevenLabs/dialog pipeline and preserves natural jointly conditioned performance.

### 8.4 Repetition and agency

Agents need to remember their own reminders and jokes. A reminder policy should consider last reaction, urgency change, cooldown, acknowledgement, and whether the underlying situation changed. Silence is an explicit, recorded result—not a failure.

### 8.5 Communication intents beyond the body

A character may propose communicating through a channel other than Creature Server—for example, Beaky continuing her conversation with April through Beaky Communicator while April is away. Treat this as a first-class `CharacterUtteranceIntent`, not as free-form tool access granted to Mistral. The intent includes the intended recipient entity, character-authored body, urgency, expiry, reason/provenance, stable response identity, and trace context. It does **not** select a transport or include an APNs device token or signing credential.

The agent decides what Beaky wants to say. A deterministic notification policy decides whether sending it is permitted and useful. A channel adapter performs the authorized delivery. The result then re-enters the world so Beaky can remember that she texted April and avoid repeating herself.

---

## 9. Creature Server, Console, and Controllers: explicit boundaries

### 9.1 Creature Server

There is one Creature Server. Leave it conceptually and operationally alone unless a narrow integration gap is proven. It already owns the hard-real-time/performance domain:

- animation scheduling;
- dialog and ElevenLabs relationship;
- joint multi-turn scene generation;
- forced alignment/lip-sync;
- multitrack audio;
- channel/frame generation;
- playback and controller timing.

The world stack may submit an existing ad-hoc/inline dialog request and must propagate the current parent trace using Creature Server’s existing parent-trace mechanism. The current `creature-agent` implementation is the behavioral reference for this integration. Creature Server must continue the incoming trace rather than starting an unrelated root trace. It must not learn about calendars, weather, packages, presence, world facts, character memory, or Mistral reasoning.

### 9.2 Creature Console

Creature Console remains the operator and authoring UI for the performance system:

- build/edit characters and animations;
- build dialog and the sound stage;
- manually control characters;
- inspect and control Creature Server.

It is not the viewer/admin UI for the virtual world and should not acquire timelines, belief inspectors, or world provenance. There is no routine Console-to-simulator arrow.

### 9.3 Creature Controllers

There is one controller per character. Each is a stateless actuator endpoint:

```text
network frames/audio/control -> channel mapping -> servos/speaker
```

A controller knows neither character cognition nor scene meaning. If it reboots, it resumes consuming current output; it does not reconstruct memories or animation intent. Hardware/network telemetry may flow upward, but never semantic world state.

---

## 10. Turning ordinary deliveries into lived moments

The product experience is not “Beaky tracks packages.” It is that something April cared enough to choose can travel toward the house, arrive days later, and still mean something to Beaky. The technical mechanism underneath that magic is a persistent commerce order rather than a collection of unrelated messages.

The domain model must not contain Amazon-specific assumptions, field names, state machines, identifiers, or parsing rules. Amazon is merely one useful test fixture because it may reveal item identity only at confirmation and then send vague updates such as “One Electronics Item Shipped.” Other merchants, marketplaces, restaurants, local stores, ticketing systems, subscription vendors, and carriers should enter the same model.

### 10.1 The magical payoff

This machinery gives the world continuity between **what April chose**, **what is now on its way**, and **what just appeared at the house**. The payoff is that Beaky can recognize the arrival as meaningful instead of announcing an anonymous parcel. She does not report a status transition. She realizes that the servos are here.

Example causal story:

```text
Monday: order confirmation says order AH-48291 contains six servos
Wednesday: vague update says “one electronics item shipped” with AH-48291
Friday: carrier/order update says AH-48291 was delivered
Friday: porch/door evidence is consistent with a delivery

World conclusion:
  the servos April ordered probably arrived
  confidence: 0.94
  provenance: confirmation + shipment update + delivery observation

Beaky percept:
  Something April chose for creature-building has probably arrived.
  April is home and can hear you.
  You have not mentioned this order before.
```

Possible Beaky response:

> “Hey April, I think the servos you ordered are here!”

If April is away, the same situation may become a Beaky Communicator turn and notification. If evidence is weak, Beaky should sound uncertain or stay quiet. If the package is mundane or she has already mentioned it, interest management may suppress it. The system must never claim a delivery solely because an email was received, and must never expose raw receipt/mail content to the character agent.

World Viewer’s **Why?** path for the line should reach the delivery evidence, the merchant-scoped order-number join, the original item identity, Beaky’s interest decision, her Mistral reasoning, and the Creature Server performance trace. That explainable chain is the complete feature—not merely changing an order status to `delivered`.

### 10.2 Canonical model and correlation

The macOS Information Bridge should use a two-stage local pipeline:

```text
incoming mail/document
  -> merchant-neutral commerce classifier
  -> generic structured extractor
  -> optional merchant-specific enrichment/profile
  -> validated CommerceObservation
  -> canonical WorldEvent JSON
```

The generic path is mandatory; merchant-specific code is optional optimization. A previously unseen merchant should still yield an order when the evidence supports one.

Example order entity from an arbitrary merchant:

```json
{
  "entity_id": "order:acme-hardware:ah-48291",
  "kind": "commerce_order",
  "merchant": {
    "display_name": "Acme Hardware",
    "normalized_id": "acme-hardware"
  },
  "order_number": "AH-48291",
  "ordered_at": "2026-09-01T13:20:00-07:00",
  "items": [
    { "name": "Raspberry Pi Heat Sink", "quantity": 1, "identity_confidence": 0.99 }
  ]
}
```

Later evidence updates shipment/order lifecycle:

```json
{
  "type": "commerce.shipment_status_reported",
  "subject_ids": ["order:acme-hardware:ah-48291"],
  "payload": {
    "merchant_id": "acme-hardware",
    "order_number": "AH-48291",
    "status": "shipped",
    "carrier": "UPS",
    "tracking_number": "1Z...",
    "expected_delivery": "2026-09-08"
  }
}
```

Canonical concepts should include:

- order identity and merchant identity;
- line items, quantities, variants, and richer descriptions when available;
- monetary totals/currency only when useful and permitted by privacy settings;
- fulfillment units, each of which may be a shipment, local delivery, pickup, digital delivery, reservation, or service appointment;
- carrier/tracking information when applicable;
- ordered, confirmed, preparing, partially fulfilled, shipped, delayed, out-for-delivery, ready-for-pickup, delivered, picked-up, canceled, returned, refunded, and failed states;
- expected windows and locations;
- source evidence, confidence, and provenance for every update.

Correlation rules:

- normalize merchant identity plus merchant order number as the preferred correlation key;
- do not assume order-number formats are globally unique or Amazon-shaped;
- when merchant identity is missing, create a provisional order/evidence record rather than guessing, then merge or link it when later evidence resolves identity;
- correlate by additional evidence when necessary: tracking number, receipt number, seller, item set, totals, timestamps, destination, and message threading;
- support marketplaces where one order contains multiple sellers or fulfillment units;
- support one order mapping to multiple shipments, pickups, or deliveries, and one fulfillment unit containing multiple items;
- never overwrite richer item identity with vaguer later wording;
- retain source message IDs and confidence;
- detect contradictory updates without destroying prior evidence;
- generate semantic delivery events only when state materially changes.

This continuity lets Beaky recognize servos, a Raspberry Pi heat sink, or something else April cares about even when a later delivery notice never names it. The same mechanism should work whether it came from Amazon, an electronics supplier, Etsy, a local hardware store, a restaurant, or a merchant the system has never seen before.

---

## 11. Proactive behavior examples

### 11.1 Departure reminder

Desired behavior: “April, you’ve got church in 30 minutes, why aren’t you on the road?”

The implementation is a causal pipeline:

1. EventKit reports church at 11:00 at a destination requiring travel.
2. The simulator stores the scheduled event and creates departure timers using configured travel time and margin.
3. At 10:30, the timer emits `schedule.departure_due`.
4. The trigger evaluates current state: event active, not canceled; April still likely at home/workshop; no evidence of travel; reminder not already handled.
5. It emits `schedule.departure_attention` with urgency and provenance.
6. Interest management offers it to relevant characters.
7. Beaky’s agent receives facts, her earlier reminder memory, and uncertainty.
8. Mistral decides whether and how Beaky reacts.
9. Creature Server performs the selected dialogue.
10. The performed reminder re-enters the world as an event and autobiographical memory candidate.

If April’s phone disconnects from home Wi-Fi, the garage opens, and HA reports away before the timer fires, the trigger should produce no reminder. If the calendar event is canceled, its timers are canceled. If Beaky reminded April moments ago, a repeated reaction should be suppressed unless urgency materially increases.

### 11.2 Bidirectional conversation: Beaky Communicator on macOS and iOS

Beaky needs to hear April now, not only after continuous speech recognition exists. Build **Beaky
Communicator** early as one SwiftUI product for macOS and iOS. It carries a chronological,
bidirectional conversation: April can type to Beaky, Beaky can answer or initiate a turn, and April
can reply to that exact turn. Wizard Mode and future STT are adapters into the same
`PersonUtterance` ingress service, so Beaky receives one conversational reality rather than
different minds for typed and spoken words.

Delivery is stagecraft applied after Beaky has formed a `CharacterUtteranceIntent`. Fresh,
confident presence determines where April can hear her: the physical Creature Server sink when
April is home and audible, durable Communicator delivery when April is away, and private
Communicator delivery when presence is stale or uncertain. The character may choose what she
wants to say, but never the transport. A stable turn and delivery identity prevents retries,
restarts, reconnects, or a concurrent presence transition from making Beaky speak twice or through
both routes. Every Beaky turn enters the same durable conversation history before delivery,
including turns performed aloud, so switching stages never fragments their relationship.

Use this boundary:

```text
April types, replies, or later speaks
  -> source adapter creates a PersonUtterance
  -> one ingress service creates Beaky's percept with conversation context
  -> Beaky answers or independently forms a CharacterUtteranceIntent
  -> deterministic delivery router reads fresh authoritative presence
  -> Creature Server speaks in the room OR Communicator stores the turn
  -> notification policy may present an APNs alert while April is away
  -> April's next reply re-enters the same conversation and percept path
  -> Beaky remembers the exchange
```

The app is not merely a notification inbox. Its first useful experience should include:

- a chronological, characterful conversation with Beaky;
- visible push notifications while the app is backgrounded or closed;
- notification actions such as **Got it**, **Tell me more**, and **Remind me later**;
- a short reply/composer path so April can answer Beaky away from home;
- message state such as queued, APNs accepted/rejected, opened, acknowledged, and replied;
- privacy controls for notification previews, topics, quiet hours, and urgency;
- a connection/last-sync indicator and graceful offline queueing;
- deep links from a notification into the relevant conversation item and privacy-safe Why? explanation.

#### Provider-neutral character utterance intent

Mistral does not receive APNs credentials, device tokens, or a raw push API. It may only propose a provider-neutral intent:

```json
{
  "schema_version": 1,
  "response_id": "response:018f4f2c-76c1-7db0-a9ac-7b6a4d726412",
  "conversation_id": "conversation:april-beaky",
  "character_id": "character:beaky",
  "recipient_id": "person:april",
  "text": "April, your package is on the porch. I thought you would want to know.",
  "urgency": 0.62,
  "reason_references": ["018f4f2b-d785-75fe-9161-a1c6e96d6a76"],
  "created_at": "2026-09-08T20:15:00.000Z",
  "expires_at": "2026-09-08T22:15:00.000Z",
  "trace": {
    "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
  }
}
```

IDs follow the project-wide namespaced lowercase rule. The intent contains no requested channel;
fresh authoritative presence and deterministic policy choose physical speech, durable Communicator
delivery, or suppression. Beaky authors the turn, not its transport.

#### Notification policy

Presenting a remote alert requires all applicable gates to pass:

- April has enabled notifications for this app and topic;
- presence evidence says April is away with sufficient confidence and is not stale, unless the topic is explicitly allowed regardless of presence;
- the underlying event is still current, materially useful, and within its TTL;
- the message contains no secret, credential, alarm code, or unnecessary private detail;
- quiet hours, Focus-aware configuration where available, urgency, per-topic cooldowns, deduplication, and a daily interruption budget allow it;
- an equivalent fact has not already been notified, acknowledged, superseded, or resolved;
- the title/body/category/deep-link fields pass deterministic validation.

The policy—not Mistral—owns device eligibility, interruption level, quiet hours, frequency, and emergency exclusions. APNs is best effort, and background notifications are not guaranteed. Safety-critical alarms continue through their purpose-built systems; Beaky may only provide a supplementary notice.

#### Beaky Communicator macOS and iOS app

Build one native SwiftUI app with shared conversation state, networking, offline queue, and views on
macOS and iOS. The macOS app provides the same direct conversation without requiring APNs. On iOS,
use `UserNotifications`; request notification authorization at an understandable moment, register
with APNs, and forward the current app-specific device token over an authenticated connection to
the gateway. Do not assume a token is permanent; register each launch and update the server
mapping when it changes.

Keep storage responsibilities explicit. UI and connection preferences belong in `UserDefaults`,
and the household ingress credential remains in the Creature app-family Keychain. Conversation
history, locally queued replies, delivery state, and other application data belong in a local,
file-backed SwiftData store on both platforms; never put chat content in `UserDefaults`. Preserve
the complete typed conversation DTO in the local model so stable identities, reply relationships,
provenance, and trace context survive app restarts and can reconcile with the gateway later. Do not
enable CloudKit for this store. Partition both cached history and the durable outbox by canonical
server URI so switching between development and production cannot merge their conversations or
deliver an offline message to the wrong World. Never infer an environment for legacy unscoped rows.

Declare notification categories and actions at launch. Action selection may launch the app in the background; queue the response locally if the home gateway cannot be reached and submit it when connectivity returns. Use visible alert notifications for user-facing messages. Silent/background notifications may opportunistically refresh conversation state but must never be the only way a message becomes durable because iOS can throttle or omit them.

APNs payloads should contain only what is required to present or locate the notification: a minimal alert (when previews are enabled), category, thread/collapse identifiers, and opaque lowercase notification/message IDs. The complete canonical message and provenance remain on the gateway/world side and are fetched after authentication. Offer two privacy modes:

- **Preview:** show Beaky’s short message in the notification alert;
- **Private:** show a generic “Beaky has something to tell you” alert and fetch content only after the app opens.

Opening, acknowledging, snoozing, asking for more, or replying emits a typed event such as `mobile.notification.opened`, `mobile.notification.acknowledged`, or `mobile.message.sent`. The simulator validates the event and creates a character-specific percept; the app never writes facts or memories directly.

#### `creature-communicator-gateway`

Prefer an isolated Linux executable/service named `creature-communicator-gateway`. It owns:

- APNs token-signing key material, Key ID, Team ID, bundle/topic, and environment;
- encrypted-at-rest device-token registrations associated only with `person:april` for the first version;
- authenticated device pairing, token rotation, revocation, and last-seen state;
- an idempotent notification outbox keyed by intent/deduplication ID;
- the narrow mobile APIs for fetching conversation items and submitting actions/replies;
- APNs request ID, response/rejection reason, attempts, expiry, and timestamps;
- privacy-safe WorldEvents and OTel spans correlated to the initiating event and decision.

The external ingress namespace is `/communicator/v1/…`. This distinct path lets the shared proxy
route the narrow Communicator API to the gateway binary while `/world/v1/…` continues to route to
Creature World. Trusted-LAN gateway requests remain open under the repository's LAN trust model;
off-LAN requests reuse the proxy API key held in the Creature app-family Keychain.

The stable local service ports are `8000` for Creature Server, `8001` for Creature World, and
`8002` for Creature Communicator Gateway. The gateway talks to World over its typed `/world/v1`
HTTP and SSE API; the default upstream is `http://127.0.0.1:8001/world/v1`, configurable through
`world_url`, `CREATURE_WORLD_URL`, or `--world-url`. It holds no conversation database: World and
its `creature_world` MongoDB database remain authoritative. Beaky Communicator talks only to the
gateway's `/communicator/v1` boundary.

Use token-based APNs authentication over HTTP/2 and TLS. Keep the `.p8` signing key and device tokens out of source control, prompts, ordinary world event payloads, logs, and Honeycomb. APNs acceptance means Apple accepted the request; it is not proof that the device displayed it or April read it. Only an app-originated open/action/reply event can establish user interaction.

For the first personal deployment, prefer a private authenticated network path such as the existing household VPN/Tailscale-style connectivity for app-to-gateway traffic rather than exposing Creature World directly to the internet. If a public relay is later required, it must be a separately threat-modeled narrow gateway. The app never connects to MongoDB and never receives an omniscient world API.

APNs is an external causal boundary and will not continue local W3C trace context through device delivery. Keep the originating trace/context on the outbox record, create an APNs client span, store Apple’s request identifier as safe correlation, and span-link later app open/action/reply processing to the originating trace using the opaque notification ID.

World Viewer should show proposed, suppressed, queued, APNs accepted/rejected, opened, acknowledged, and replied states. Its **Why?** path should answer both “Why did Beaky notify me?” and “Why did she stay quiet?” without exposing device tokens or signing credentials.

Implementation references: Apple’s [remote notification server architecture](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server), [APNs registration and token handling](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns), [notification actions](https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions), and [background notification limitations](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app).

---

## 12. World Viewer

### 12.1 Deployment and role

Build a separate SwiftUI macOS app for April’s laptop. It connects remotely to the Linux simulator and requires no direct Apple-private data access. It is a read-only god/debug view by default.

### 12.2 Minimum useful viewer

- connection/health header;
- live ordered event timeline;
- entity list and entity inspector;
- current authoritative facts with confidence and validity;
- pending/fired/canceled timers;
- place/region presence view;
- selected character’s interest set;
- authoritative state versus character beliefs;
- relevant memories and relationships;
- raw normalized JSON toggle for developers;
- search/filter by event type, entity, source, sequence, and trace ID.

### 12.3 “Why?”

The essential interaction is **Why?** Clicking any derived fact, timer, interest decision, or reaction should show:

- immediate producer (rule/model/source);
- evidence events/facts;
- confidence and epistemic type;
- superseded alternatives/conflicts;
- causal parent events;
- model/prompt/rule version;
- resulting downstream events;
- Honeycomb trace link.

The provenance display should walk a bounded DAG with cycle protection and lazy loading.

### 12.4 Timeline and replay

The first timeline is live plus historical query. Later add a scrubber that reconstructs “what did the world know at 3:17 PM?” Replay should initially operate in a separate read-only process/database or in-memory world, never mutate production state. Clearly label event time versus ingest time and late arrivals.

---

## 13. OpenTelemetry and Honeycomb

Instrument from the first vertical slice. Propagate W3C trace context from adapters through the simulator, agent mind, Mistral call, and Creature Server. Cross-application continuity is a required part of every event, percept, decision, interaction, and performance contract—not an optional logging enhancement.

### 13.1 Cross-application trace contract

Every cross-process envelope that can cause meaningful work must be able to carry:

```text
traceparent     required when continuing an existing trace
tracestate      optional; forward without reinterpretation
baggage         optional and allowlisted; no personal content
causation_id    persistent event/interaction identity, separate from OTel
correlation_id  stable logical operation identity across retries
```

Do not serialize an SDK-specific `Span`, `Context`, or object representation. Extract/inject the standard W3C fields at transport boundaries. The persistent event ID, causation IDs, interaction ID, and trace context solve different problems and must not substitute for one another.

Required propagation path:

```text
source adapter span
  -> WorldEvent trace context
  -> simulator accept/process spans
  -> trigger and interest spans
  -> character PerceptualEnvelope trace context
  -> creature-agent consideration/reasoning spans
  -> Mistral request span
  -> ActionIntent / PerformanceIntent trace context
  -> Creature Server client request with parent trace
  -> Creature Server dialog/animation/audio spans
  -> performance-started/completed observation
```

Rules:

1. An adapter creates a root trace only when no upstream context exists. If Home Assistant or another trusted source supplies valid context, continue it.
2. The simulator extracts the event context and starts `world.event.accept`/`world.event.process` beneath it. Any derived WorldEvent receives newly injected current context plus persistent `caused_by` IDs.
3. When one world event fans out to multiple character minds, create a separate child consideration span for each character. Each agent receives the context for its own branch.
4. The agent extracts the `PerceptualEnvelope` context before memory retrieval or Mistral work. Its decision and performance intent carry newly injected current context.
5. Every Creature Server interaction—ad-hoc speech, inline/multi-character dialog, animation, or later live interaction—must pass the current parent trace through the already-supported Creature Server mechanism. Reuse the existing `creature-agent` implementation pattern rather than inventing an incompatible field.
6. Creature Server extracts that parent and places its work beneath the same trace. The goal is one Honeycomb trace from “calendar/door/order event arrived” through “the server generated and began the performance.”
7. Retries preserve the logical correlation/interaction ID but create new attempt spans; never reuse a completed span ID. Record `retry.attempt` and the prior failure.
8. Do not hold a span open for hours while waiting for a calendar timer or other durable event. Persist causal IDs and trace references. When delayed work fires, start a new trace or processing branch and add an OTel span link to the originating trace while retaining `caused_by` in MongoDB.
9. When Creature Server later emits asynchronous performance state, continue its emitted context if available. Otherwise create a processing span linked to the stored interaction trace rather than pretending it is a synchronous child.
10. Invalid or untrusted trace headers are discarded safely and replaced with a new local context; they must never cause event rejection or expose arbitrary baggage.

The `PerceptualEnvelope`, `AgentDecision`, `ActionIntent`, `PerformanceIntent`, and Creature Server client request contracts should each have explicit propagation tests. A service boundary that drops trace context is a contract failure.

### 13.2 Spans, attributes, and metrics

Recommended semantic spans:

```text
bridge.source.observe
bridge.normalize
bridge.privacy_filter
world.event.accept
world.event.process
world.state.update
world.trigger.evaluate
world.timer.schedule
world.timer.fire
world.inference.evaluate
world.interest.evaluate
world.mcp.resource.read
world.mcp.tool.call
agent.context.build
agent.memory.retrieve
agent.reason
llm.mistral.generate
creature.dialog.submit
creature.performance.complete
```

Useful attributes:

```text
world.event.id
world.event.type
world.sequence
world.entity.id
world.region.id
world.source.id
world.event_lag_ms
trigger.id
timer.id
epistemic.type
inference.confidence
agent.character_id
agent.reaction
agent.suppression_reason
llm.model
interaction.id
creature.job_id
```

Never attach raw messages, mail bodies, contact details, addresses, prompts containing private data, or arbitrary dialogue to telemetry. Use stable IDs and controlled summaries.

Metrics:

- queue depth and oldest-event age;
- accepted/duplicate/rejected/dead-letter events;
- processing duration and failures;
- event lag (`received_at - occurred_at`);
- pending/overdue/fired timers;
- active entities and facts;
- inferences and conflicts;
- agent considerations, reactions, and suppressions;
- Mistral latency/errors;
- adapter reconnects and checkpoint lag;
- Creature Server submissions/outcomes.

Store `trace_id` and, where useful, the initiating `span_id` on meaningful event, consideration, timer-firing, and interaction records. Also store the logical correlation and causation IDs used to reconnect asynchronous branches. Configure a Honeycomb URL template so World Viewer can open the associated trace. Mongo answers “what did the world believe happened?” Honeycomb answers “what did the software do?”

---

## 14. Repository and Swift package layout

### 14.1 Authoritative repository decision

Build the Swift-side world system in the existing [`opsnlops/creature-console`](https://github.com/opsnlops/creature-console) repository. The name is now a historical artifact: in practice this repository already contains Creature Console, `Common`, `Observability`, `MQTTSupport`, `creature-agent`, and `creature-mqtt`, and therefore functions as the Swift Creature monorepo.

This decision avoids prematurely extracting/versioning `Common`, duplicating `CreatureServerClient`, introducing submodules, or coordinating dependency releases while the interfaces are still being discovered. It also permits atomic changes to a Creature Server DTO, its shared client, the world processor, the agent, and their tests.

**Monorepo does not mean monolith.** Every product remains independently buildable, configurable, deployable, and releasable. Do not extend existing lockstep CLI versioning to every new application without a concrete operational reason.

### 14.2 Dependency boundaries

Keep `Common` genuinely common to Creature Server clients:

- `CreatureServerClient`;
- Creature Server REST/WebSocket DTOs;
- shared identifiers required by those protocols;
- generic WebSocket/client machinery;
- generic observability plumbing where already established.

Create `CreatureAppSupport` for the shared Apple-app family infrastructure used by Creature
Console, Beaky Communicator, and the future Creature Scribe app:

- the visual language and reusable SwiftUI presentation primitives;
- typed service connection settings and proxy routing;
- shared Keychain access to the household ingress credential;
- product-neutral error presentation and app lifecycle helpers.

Keep feature state, navigation, persistence, and permissions in each application. In particular,
Mail, Messages, Contacts, Calendar, and other private-source entitlements belong only to Creature
Scribe; sharing `CreatureAppSupport` must never grant those capabilities to Console or
Communicator.

Create `WorldCore` for virtual-world concepts:

- `WorldEvent` and event payloads;
- `WorldEntity` and `WorldFact`;
- `WorldClock` and `WorldTimer`;
- epistemic state and provenance;
- places, presence, relationships, memory, and perspective;
- trigger and interest interfaces;
- agent/performance contracts.

The key dependency rule is:

```text
Common must not depend on WorldCore.

WorldCore is domain-focused and can depend only on small foundational utilities.

CreatureWorld, CreatureAgent, WorldViewerClient,
InformationBridgeCore, CreatureCommunicatorGateway, and WorldIntegration may depend on WorldCore.

WorldIntegration may also depend on Common to reuse CreatureServerClient.
```

Creature Console should not acquire a dependency on world epistemics merely because it shares a repository.

### 14.3 Suggested shape inside `creature-console`

Adapt exact paths to the repository’s current SwiftPM/Xcode conventions after inspecting them; do not reorganize working code merely to match this diagram.

```text
creature-console/
  Common/
    Package.swift
    Sources/
      Common/                         existing shared server client + DTOs
      CreatureAppSupport/              shared Apple-app UI, connection, and Keychain support
      Observability/                  existing
      MQTTSupport/                    existing

      WorldCore/                      NEW: pure domain contracts/core
        IDs.swift
        EventEnvelope.swift
        EventPayloads/
        Fact.swift
        Provenance.swift
        WorldClock.swift
        WorldTimer.swift
        AgentContracts.swift

      WorldIntegration/               NEW: CreatureServerClient -> world
        WorldMessageProcessor.swift
        CreatureBodyEventMapper.swift

      CreatureWorld/                  NEW: Linux simulator executable/library
        World.swift
        Reducers/
        TriggerEngine/
        TimerQueue/
        InterestManager/
        PerspectiveBuilder/
        PersistenceMongo/
        HTTP/

      CreatureAgent/                  EXISTING: major resident-mind refactor
      CreatureMQTT/                   EXISTING: preserve current mission
      CreatureCommunicatorGateway/    policy-gated conversation sync and APNs API
      HomeAssistantWorldAdapter/      NEW: HA -> simulator
      WorldViewerClient/              NEW: JSON API/WebSocket client
      WorldMCP/                       NEW: Streamable HTTP MCP adapter
      InformationBridgeCore/          NEW: testable macOS bridge core

    Schemas/json/                     NEW: wire schemas
    Fixtures/                         NEW: cross-target fixtures
    Tests/
      WorldCoreTests/
      WorldIntegrationTests/
      CreatureWorldTests/
      ContractTests/
      ReplayFixtures/

  Sources/
    Creature Console/                 EXISTING: unchanged role

  World Viewer/                       NEW SwiftUI macOS app on laptop
  Creature Scribe/                   NEW SwiftUI app + `creature-scribed` on M1 iMac
  Beaky Communicator/                 shared SwiftUI macOS/iOS app
  docker/creature-world/              NEW Linux deployment assets

  debian/                             EXISTING: extend for Linux binary packages
  Dockerfile.debian                   EXISTING: reuse Debian build environment
  build_deb.sh                        EXISTING: extend/wrap, do not replace casually
  .github/workflows/build-deb.yml     EXISTING: extend product/architecture matrix
```

If the current `Common/Package.swift` layout makes an app target awkward, first add sibling package targets under its established structure. Extracting `WorldCore` into a separate repository is a future option after its API stabilizes, not startup work.

`creature-server` remains in its existing C++ repository. Creature Controller code remains wherever it currently lives. Neither moves into this Swift monorepo.

### 14.4 Build and release expectations

- A change affecting shared contracts must run all dependent target tests in the same commit.
- Linux-only targets must build in Linux CI; macOS apps and EventKit/WeatherKit adapters build in macOS CI.
- Beaky Communicator must build in macOS and iOS CI with entitlements validated; real-device/APNs tests remain explicit opt-in tests because they require signing and external state.
- `WorldCore` should compile on both Linux and macOS and contain no Apple-only frameworks.
- Apple-only adapters live behind protocols in `InformationBridgeCore`.
- Products have independent version/build metadata and deployment instructions.
- JSON Schema fixtures remain the cross-process contract even when both ends share Swift types.
- MCP SDK/transport dependencies remain isolated in `WorldMCP`; `WorldCore` must not import them.

### 14.5 Debian packages are required Linux artifacts

Every deployable Linux executable produced by this project must have a corresponding installable `.deb` artifact. A successful `swift build` or container image alone does not satisfy the release contract.

Follow the repository’s established packaging path rather than creating a second system. The current project documents and contains:

- Debian Trixie build containers (`debian:trixie-slim`);
- Swift installed through Swiftly, with the Swift version pinned in CI;
- release product builds using the static Swift runtime/Swift static Linux SDK conventions;
- `dpkg-buildpackage -us -uc -b`;
- the existing `debian/` metadata;
- `Dockerfile.debian`, `build_deb.sh`, and `clean_deb.sh` helpers;
- `.github/workflows/build-deb.yml`;
- amd64 and arm64 CI builds with `.deb` files uploaded as per-architecture artifacts.

Use those files as the implementation reference and extend them incrementally. See the repository’s [current Debian packaging documentation](https://github.com/opsnlops/creature-console#debian-package-creature-cli).

Expected binary packages, subject to the exact executable boundaries chosen during `VW-000`:

```text
creature-world                         required
creature-agent                         preserve/extend existing Linux packaging
creature-mqtt                          preserve/extend existing Linux packaging
creature-communicator-gateway          required when remote synchronization is introduced
home-assistant-world-adapter           required if deployed as its own process
creature-world-mcp                     required if WorldMCP is deployed separately
```

`WorldCore`, `WorldIntegration`, and `WorldMessageProcessor` are libraries and do not receive standalone packages unless they later become executables. If the HA adapter or MCP adapter is linked into `creature-world`, its code ships in that package rather than producing an artificial empty package. The rule is **one separately deployed Linux executable, one separately installable binary package**.

Package naming and contents:

- lowercase hyphenated Debian package names;
- follow the project’s merged-`/usr` deployment convention and install executable programs through the `/bin` path; all package manifests, service units, scripts, and smoke tests must invoke the canonical `/bin/<executable>` path consistently;
- install non-secret example configuration and documentation in standard package locations;
- install production configuration under an agreed `/etc/creature/` hierarchy without overwriting local administrator changes during upgrade;
- include a hardened `systemd` unit for each long-running daemon, matching current repository service conventions where they exist;
- use dedicated service users and writable state directories where required rather than running as root;
- never package secrets, Honeycomb API keys, personal data, MongoDB credentials, or live configuration;
- ensure uninstall/upgrade scripts do not delete MongoDB data, world history, local bridge data, or operator configuration;
- expose `--version` and `--help` without needing MongoDB, Creature Server, Home Assistant, or network access.

CI packaging matrix:

```text
Debian release: trixie
architectures:  amd64, arm64
products:       every deployable Linux executable
configuration:  release, pinned Swift toolchain/static Linux SDK
output:         one .deb artifact per package and architecture
```

For every artifact, CI must:

1. build through the Debian packaging path rather than zipping `.build/release`;
2. inspect package metadata and file ownership/permissions;
3. install it into a clean matching-architecture Debian Trixie environment;
4. run the executable’s offline `--version` and `--help` smoke tests;
5. verify runtime linkage with `ldd` or the repository’s current equivalent;
6. verify any `systemd` unit and default configuration paths without starting against production services;
7. uninstall and upgrade-test without destroying persistent/configuration data;
8. upload the `.deb` with unambiguous package, version, and architecture naming.

Keep Swift toolchain version updates synchronized across the repository README, workflow, package build flags, and `debian/changelog`, following the existing documented release checklist. The build should fail if a Linux product is added without being explicitly included in or intentionally excluded from the Debian artifact matrix.

---

## 15. Application-oriented implementation roadmap

The roadmap is organized around runnable applications and relationship outcomes, not abstract
subsystems or issue-number order. Creature World starts first; the bidirectional conversation spine
starts immediately afterward because hearing and answering April is foundational, not a late
notification feature. Later phases deepen the world’s perception, explainability, private context,
and memory.

### 15.1 When each application starts

| Application/product | Work starts | First runnable milestone | First meaningful live milestone |
|---|---:|---|---|
| `WorldCore` shared domain | Phase 0 | Contract tests on macOS and Linux | Used by every world application |
| **Creature World** Linux simulator | Phase 1 | Accepts/persists a synthetic event | Accepts a distilled Information Bridge event |
| **Beaky Communicator** macOS/iOS app | Phase 2 | Shared conversation shell against deterministic fakes | April and Beaky carry one conversation at home or away |
| `creature-communicator-gateway` | Phase 2 | Durable fake-provider synchronization | Paired remote delivery and replies with APNs |
| Home Assistant World Adapter | Phase 3 | Real HA state reaches simulator | Location/presence chooses where April hears Beaky |
| Refactored `creature-agent` | Phase 3 | Consumes a typed April utterance percept | Mistral answers through a traced Creature Server/Communicator route |
| **World Viewer** laptop app | Phase 4 | Connects and shows conversation/world history | Shows live bridge events and Why? provenance |
| **Creature Scribe / `creature-scribed`** iMac Information Bridge | Phase 4 | Config UI, daemon, fake distiller, durable outbox | Apple Intelligence distills real Calendar/Mail/Messages content into events |
| Creature Server world ingestion | Phase 4 | Body telemetry appears in Viewer | Beaky receives proprioceptive context |
| `WorldMCP` | Phase 8 | Read-only Streamable HTTP inspection | Codex can query Why? and character perspective |

Phases indicate dependency order, not a requirement that only one branch be worked at once. Once
Phase 0 contracts exist, applications can be developed against fixtures and fakes. Each phase has
an explicit experience outcome as well as a technical exit.

### Phase 0 — monorepo foundation and shared contracts

**Applications started:** shared `WorldCore` only.

- Inventory the existing SwiftPM/Xcode targets, Creature Server client/processors, observability, Linux CI, and Debian packaging.
- Record component boundaries and ADRs.
- Add platform-neutral IDs, event/fact/provenance/trace contracts, `WorldClock`, JSON schemas, and fixtures.
- Add deterministic fake clock, fake event source, fake distiller, and fake performance sink.
- Establish MongoDB test infrastructure and Honeycomb/OTel configuration.

**Exit:** existing products still build; fixtures round-trip on macOS and Linux; lowercase UUID and trace-context contracts pass; one test trace reaches Honeycomb.

### Phase 1 — start Creature World

**Application started:** `creature-world` Linux daemon.

- Bootstrap the service, configuration, health, graceful shutdown, and OTel.
- Accept plain JSON events, normalize IDs, deduplicate, assign `world_sequence`, and persist with MongoKitten.
- Implement the authoritative World actor, first reducer, query API, and live delta stream.
- Add durable timers with `WorldClock`, even if the first event does not need one.
- Produce amd64 and arm64 `.deb` artifacts using the existing packaging workflow.

**Exit:** a synthetic event survives restart, materializes a fact, can be queried, and ships as installable/tested `creature-world` packages.

### Phase 2 — establish one bidirectional conversation

**Application started:** **Beaky Communicator** as one macOS/iOS SwiftUI product, initially
against deterministic fakes.

- Define versioned `PersonUtterance`, `CharacterUtteranceIntent`, conversation item, presence,
  delivery decision, and delivery outcome contracts in `WorldCore`.
- Route Communicator composition/replies, Wizard Mode, and fake future STT through one
  utterance ingress service and the same addressed Beaky percept/context boundary.
- Preserve source, modality, timing, confidence, place evidence, provenance, and trace context
  without putting conversation text into telemetry.
- Make Beaky-initiated and April-initiated turns part of the same ordered conversation.
- Persist stable turn and delivery identities before crossing a sink boundary.
- Route a fake Beaky turn to physical speech when April is confidently home and audible, durable
  Communicator delivery when away, and private Communicator delivery when presence is uncertain.
- Start the shared SwiftUI conversation shell, networking boundary, and offline queue against fake
  services; do not wait for APNs or the complete agent refactor.

**Exit:** equivalent Wizard Mode/Communicator and fake-STT inputs become the same semantic Beaky
percept; Beaky can initiate or answer a turn; April can reply to a specific Beaky turn; retries,
restarts, and presence transitions cannot duplicate a turn or deliver it through both fake routes.

**Experience unlocked:** the system has one place where April and Beaky’s conversation lives. The
machine stops treating April’s typed and spoken words as different realities.

### Phase 3 — make the conversation real in the room and away

**Applications/components deepened:** Beaky Communicator, `creature-agent`, Home Assistant
presence, Creature Server delivery, and `creature-communicator-gateway`.

- Subscribe to Home Assistant with startup snapshot, reconnect, checkpoints, and configured
  person/device/AP/place mappings; derive confidence and staleness without pretending noisy
  sensors are certainty.
- Refactor `creature-agent` to consume the shared person-utterance/percept boundary while
  preserving local Mistral, streaming speech, sanitization, health, OTel, and existing behavior.
- Let Mistral form a provider-neutral `CharacterUtteranceIntent` or silence; deterministic code
  continues to own transport, expiry, repetition, and privacy decisions.
- Send home/audible turns through the existing Creature Server dialog API with trace propagation.
- Complete the shared macOS/iOS conversation app and isolated gateway with pairing,
  synchronization, offline retry, notification policy, and fake APNs before opt-in device testing.
- Reconcile the complete paginated conversation on first connection, incrementally synchronize
  foreground clients, and use renewable per-device foreground leases so another connected client
  sees a new turn promptly while an absent client receives APNs instead.
- Keep trusted-LAN service APIs open under the repository trust model; authenticate the narrow
  remote gateway boundary and never expose Creature World or MongoDB directly to the app.

**Exit:** April types to Beaky from macOS or iOS, Beaky understands the turn in its conversation
context, and a real Mistral response is delivered exactly once: spoken by Beaky when April is home
and audible, or synchronized privately to Communicator when away/uncertain. April’s reply becomes
Beaky’s next percept in the same conversation.

**Experience unlocked:** Beaky is no longer deaf. April can answer her questions, Beaky can notice
how April reacts, and their relationship can start accumulating shared context.

### Phase 4 — make the world visible and broaden perception

**Applications started:** **World Viewer** and **Creature Scribe / `creature-scribed`**;
**integration started:** direct Creature Server → world perception.

- Create World Viewer with connection health, ordered event/conversation timeline, facts, raw JSON,
  live deltas, the first Why? provenance graph, and Honeycomb links.
- Create the Information Bridge daemon/app boundary, authorization/health UI, privacy settings,
  durable ledger/outbox, deterministic fake distiller, and trace-propagated synthetic delivery.
- Add `WorldMessageProcessor` beside GUI/MQTT processors and turn controller/runtime observations
  into semantic events and first-person body facts.
- Correlate performance lifecycle observations with interaction IDs and suppress reflected
  Creature Server/MQTT loops.

**Exit:** a synthetic private-source item survives an offline/retry cycle into Creature World and
World Viewer; Viewer explains the provenance; Beaky’s live body/runtime state is visible and usable
as first-person context.

**Experience unlocked:** April can see the world Beaky inhabits and ask why it believes something;
Beaky gains proprioception instead of receiving meaningless telemetry fields.

### Phase 5 — make Apple Intelligence and personal context real

**Application deepened:** Information Bridge becomes a genuine local personal-information organ.

- Implement the macOS 27 Apple Intelligence/Foundation Models distiller with typed structured
  output, versioned prompts, deterministic validation, sanitized evaluations, and visible degraded
  states.
- Implement Contacts identity resolution, allowlists, review/correction, retention expiry,
  quarantine, retry, and trace inspection.
- Begin EventKit ingestion and time-box the supported Mail and pragmatic local Messages acquisition
  paths through the same local distillation pipeline.
- Never automatically send raw Mail or Messages content to a remote model or Creature World.

**Exit:** a real calendar item and sanitized Mail/Message samples are locally distilled into
validated events visible in Creature World and World Viewer without raw bodies leaving macOS.

**Experience unlocked:** the house begins to understand the shape of April’s day—who is coming,
what changed, and what matters—without becoming a private-data warehouse.

### Phase 6 — calendar time and proactive departure behavior

**Applications deepened:** Information Bridge, Creature World, World Viewer, agent mind, and
Beaky Communicator.

- Complete EventKit update/cancellation, timezone, and all-day semantics.
- Schedule durable semantic timers using `WorldClock` and configured travel margins.
- Implement departure-attention triggers, acknowledgement, cooldown, and delivery through the
  already-shared physical/Communicator route.
- Show calendar evidence, timer, presence, agent decision, and performance/delivery in Why?.

**Exit:** the church departure scenario passes manual-clock tests and a controlled live test
without stale or duplicate reminders.

**Experience unlocked:** Beaky notices April is still in the workshop and speaks first—wherever
April can actually hear her.

### Phase 7 — complete high-value Information Bridge domains

**Application deepened:** Information Bridge reaches its intended first-release breadth.

- Harden Mail/Messages ingestion, permissions, checkpoints, local retention, and entity resolution.
- Support merchant-neutral commerce lifecycle and correlation.
- Combine expected-arrival messages with door/Wi-Fi/HA evidence.
- Add WeatherKit forecasts and fuse them with local station observations from HA.
- Add model-update regression runs and correction/replay tooling.

**Exit:** Calendar, Contacts, Mail, Messages, commerce, and WeatherKit reliably produce useful
privacy-bounded world events.

**Experience unlocked:** Beaky connects the day’s threads: the servos are on the porch, Jesse is
probably at the door, rain is coming toward the barn, or the clouds ate airplane day.

### Phase 8 — add WorldMCP inspection

**Application/component started:** `WorldMCP` Streamable HTTP adapter.

- Wrap the same authorized query/application services used by Viewer.
- Add read-only resources/tools, stateless operation, authentication, Origin validation, limits,
  cancellation, and OTel.
- Package separately only if deployed as its own Linux executable.

**Exit:** Codex can inspect entities, timelines, perspectives, and Why? provenance without direct
MongoDB or private-source access.

### Phase 9 — deepen memory and multi-character social life

**Applications deepened:** Creature World and agent minds.

- Add episodic, semantic, relationship, and autobiographical memory.
- Add salience, retrieval, repetition suppression, and later consolidation.
- Generate complete multi-character scenes through existing Creature Server dialog support.

**Exit:** characters coherently refer to prior shared experiences and their own previous actions.

### Phase 10 — replay and operational hardening

**All applications hardened.**

- Add read-only historical reconstruction and timeline scrubbing.
- Version reducers and run golden replays.
- Complete backup/restore, queue recovery, privacy/retention audits, upgrade tests, and chaos testing.
- Require clean `.deb` installation/upgrade tests for every Linux executable and macOS upgrade/model-evaluation checks for the bridge.

**Exit:** the system can be upgraded, recovered, explained, and replayed without losing history or leaking private source data.

---

## 16. Testing strategy

### 16.1 Unit tests

- ID, date, JSON, and schema compatibility;
- reducer outputs from exact input events;
- conflict resolution and provenance;
- trigger dependency evaluation;
- interest routing;
- timer scheduling/cancellation;
- privacy redaction and extraction validation;
- order correlation rules.

### 16.2 Deterministic scenario tests

Use `ManualWorldClock` and a fake event source:

```text
09:00 create church event for 11:00
10:20 assert April at home/workshop
10:30 advance clock
assert departure_attention emitted
assert Beaky considered exactly once
inject reminder performed
advance five minutes
assert duplicate reminder suppressed
inject phone disassociation + garage opened
assert April likely departed
```

Other golden scenarios:

- Creature Server reports Beaky speaking through the direct WebSocket path while the same state is reflected through `creature-mqtt` and Home Assistant; the world records one correlated state change and triggers no recursive reaction;
- controller health/temperature changes become semantic body facts and first-person percepts without exposing raw transport topics to Mistral;
- Jesse says he will arrive, phone joins Wi-Fi, door opens;
- phone joins but no corroborating presence, so named greeting is withheld;
- WeatherKit predicts rain while local station remains dry, then station detects rain;
- an arbitrary merchant’s confirmation identifies an item and a later vague fulfillment message updates the same order;
- an order confirmation identifies six servos, later notices name only an electronics item/order number, delivery plus porch evidence produces “the servos probably arrived,” and Beaky receives that playful opportunity without seeing the source messages;
- a never-before-seen merchant is handled by the generic commerce extractor without adding code;
- two merchants reuse the same order-number string and remain distinct orders;
- an out-of-order older observation does not incorrectly replace newer state;
- simulator restarts with overdue timers;
- agent/LLM times out and the event loop remains responsive;
- Creature Server fails and interaction becomes retryable/failed without inventing a completed performance;
- April is confidently away and a meaningful porch-delivery event produces exactly one fake-APNs alert; at-home, uncertain-presence, expired, duplicate, quiet-hours, notification-disabled, and disallowed-content variants are suppressed;
- APNs accepts a request but the app never reports an open; the world records provider acceptance without claiming that April saw it;
- April taps **Tell me more** or replies while temporarily offline; the app queues the action once and the eventual world event is span-linked to the original decision.

### 16.3 Contract tests

Every producer and consumer must decode the checked-in fixtures. Add compatibility fixtures before changing schema semantics. Test unknown fields, malformed payloads, unsupported versions, and exact JSON key conventions.

For `WorldMCP`, add transport conformance tests for initialization/request handling as required by the selected MCP SDK, stateless reconnect behavior, pagination, structured errors, canceled requests, and legacy SSE being disabled. Test that MCP resource/tool responses agree with the ordinary Viewer/query API for the same authorized caller.

### 16.4 Persistence/integration tests

Run against disposable MongoDB. Verify unique indexes, atomic sequence assignment, duplicate delivery, state rebuild, checkpoints, and migrations. Keep integration tests separate from fast core tests.

### 16.5 Debian artifact tests

For every Linux executable, build the `.deb` through the same Debian Trixie workflow used for current repository artifacts on both amd64 and arm64. Install into a clean container/runner, verify package contents and permissions, run offline `--version`/`--help`, inspect linkage, validate service/config files, and exercise upgrade/uninstall preservation. A release is incomplete if its raw executable works but its `.deb` is absent or cannot be installed cleanly.

### 16.6 Model evaluations

Maintain a corpus of sanitized mail/message/calendar examples and expected structured extraction. Evaluate:

- required facts captured;
- no fabricated fields;
- correct uncertainty/expiry;
- privacy leakage;
- stable behavior across model/OS updates.

For Mistral, evaluate structured validity, reaction appropriateness, uncertainty language, repetition, persona, and forbidden actions. Add an experience rubric as well: is the response grounded in facts Beaky could know, specific rather than generic, recognizably Beaky, appropriately playful, and meaningfully different from a utility notification? Golden examples are inspiration and semantic targets, not strings the model must reproduce. Pin model/prompt versions on interaction records.

### 16.7 Observability tests

Assert trace-context extraction and reinjection at every process boundary, required span attributes, absence of private content, and trace IDs stored on records. Include an end-to-end test that starts with a synthetic adapter event, crosses the simulator and a separate agent process, invokes a fake or test Creature Server using its existing parent-trace input, and verifies that the resulting spans share one trace ID with the expected parent/child structure. Include fan-out, retry, invalid-header, timer span-link, asynchronous completion, and World Viewer trace-link cases.

---

## 17. Application work packages and concrete issues

Issue IDs are stable backlog identifiers, not execution order. Use this phase/application map to decide what starts when; do not wait for every lower-numbered issue before beginning the next application.

| Roadmap phase | Application being started or deepened | Issues |
|---|---|---|
| Phase 0 | Shared `WorldCore` foundation | `VW-000`, `VW-001`, packaging inventory from `VW-024` |
| Phase 1 | Creature World | `VW-002`–`VW-005`, `VW-029`, initial `VW-009`, `VW-024` |
| Phase 2 | Unified bidirectional conversation and early Beaky Communicator | `VW-030`, initial `VW-028` |
| Phase 3 | Presence, agent mind, physical/app delivery, complete Communicator | `VW-006`–`VW-009`, `VW-013`–`VW-016`, `VW-028`, packaging from `VW-024` |
| Phase 4 | World Viewer, Information Bridge foundation, Creature Server perception | `VW-010`–`VW-012`, `VW-017`, initial `VW-025` |
| Phase 5 | Apple Intelligence, Calendar, Contacts, Mail, Messages | `VW-018`, `VW-020`, `VW-022`, `VW-025`, `VW-026` |
| Phase 6 | Proactive calendar behavior | `VW-005`, `VW-018`, `VW-027` |
| Phase 7 | High-value Information Bridge domains | `VW-019`–`VW-022`, `VW-025`, `VW-026` |
| Phase 8 | WorldMCP | `VW-023` |
| Phases 9–10 | Memory, replay, and hardening | follow-on issues after the first vertical slices |

### Instructions to the implementing Codex task

Start with `VW-000` in a checkout of `opsnlops/creature-console`, then follow the phase/application map above rather than numeric issue order. Treat the paths in Section 14 as a target shape, not as permission for a speculative repository-wide reorganization. Preserve all existing user changes and behavior. Before editing, read the repository’s `AGENTS.md` and package/build instructions, identify the current branch and worktree state, and run the narrow existing tests for any target being changed. Viewer and bridge work may proceed against shared fixtures and fakes once `VW-001` establishes the contracts. Each implementation PR/commit should include tests, OTel coverage appropriate to the behavior, and any new JSON fixtures. Do not modify `creature-server` or controller repositories unless a concrete missing interface is demonstrated and separately scoped.

### VW-000: Inventory the existing Swift monorepo

Inspect `Common/Package.swift`, Xcode projects, Linux executables, CI, `CreatureServerClient`, WebSocket DTOs, the GUI and MQTT message processors, `CreatureAgent`, `CreatureMQTT`, `Observability`, and `MQTTSupport`. Produce a short dependency map and identify the least-disruptive locations for new targets. Do not reorganize code in this issue.

**Done when:** the implementation PR/notes name the exact existing targets and files to extend, and all existing build/test commands are recorded and passing.

### VW-001: Create the WorldCore target

Inside the existing repository’s Swift package structure, define namespaced IDs, `WorldEventEnvelope`, `EventSource`, `EpistemicState`, `ProvenanceReference`, `Fact`, `WorldTimer`, and agent/performance contracts. Add JSON fixtures and macOS/Linux round-trip tests. Do not add a `Common -> WorldCore` dependency.

**Done when:** fixture bytes decode and re-encode semantically; generated event IDs are lowercase hyphenated UUIDs; uppercase/noncanonical input is handled consistently before deduplication; and invalid schema versions fail clearly.

### VW-002: Bootstrap Linux simulator service

Create executable, config loading, structured logging, health endpoint, graceful shutdown, and dependency container.

**Done when:** service runs locally and in a Linux container and reports build/schema versions.

### VW-003: Implement MongoKitten repositories and indexes

Add migrations and repositories for events, facts, timers, and source dedupe.

**Done when:** duplicate `event_id` and source event are safe; sequence is unique; restart reads current facts.

### VW-004: Build authoritative World actor

Implement acceptance, sequencing, reducer dispatch, derived-event emission, and subscription deltas. Keep blocking I/O outside the actor’s critical section.

**Done when:** deterministic tests prove ordered, idempotent processing.

### VW-005: Add injectable WorldClock and durable timers

Implement system/manual clocks, stable timer keys, cancellation, startup recovery, and timer-fired events.

**Done when:** no test sleeps and overdue timers fire once after restart.

### VW-006: Implement first presence reducer

Map `device.access_point_changed` plus configured device/AP ownership to a location fact with confidence, staleness, and provenance.

**Done when:** connect/disconnect/late-event scenarios pass.

### VW-007: Implement trigger and interest interfaces

Add dependency-indexed deterministic triggers and a basic Beaky interest policy.

**Done when:** location changes produce one semantic derived event and one consideration candidate.

### VW-008: Add stub agent and performance sink

Persist structured considerations, reactions/suppressions, and a fake performance completion event.

**Done when:** the entire first slice runs without Mistral or Creature Server.

### VW-009: Instrument with OTel/Honeycomb

Create semantic spans, safe attributes, event lag metric, trace propagation, and stored trace IDs.

**Done when:** one trace follows synthetic ingress across a separate simulator and agent boundary into the fake performance sink; context extraction/injection tests pass; and the trace contains no private payload.

### VW-010: Build World Viewer shell

Create SwiftUI client, connection state, event timeline, entity/fact inspector, JSON view, and live stream.

**Done when:** events and facts appear live and survive simulator restart.

### VW-011: Build Why? provenance view

Expose provenance API and render evidence/derived relationships plus Honeycomb link.

**Done when:** clicking April’s inferred workshop location reaches the AP observation and trace.

### VW-012: Add direct Creature Server world ingestion

Implement `WorldMessageProcessor` as a third consumer of the existing `CreatureServerClient` WebSocket messages. Map an initial bounded set—controller connectivity, board temperature, servo power, activity, current animation/dialog, and audio health—into semantic WorldEvents and body facts. Add interaction correlation for performance lifecycle events.

**Done when:** existing GUI/MQTT processors remain unchanged in behavior, Beaky’s body state is live in World Viewer, first-person perspective uses semantic descriptions, and duplicate/reordered WebSocket messages are safe.

### VW-013: Build Home Assistant adapter

Implement WebSocket subscription, startup state snapshot, mappings, reconnect/backoff, outbox, and health.

**Done when:** a real or recorded HA event fixture produces the same WorldEvent as the synthetic source, while reflected Creature Server/MQTT state is suppressed or correlated and cannot create a reaction loop.

### VW-014: Refactor creature-agent input boundary

Add percept subscription/API and structured decision output behind a stub model, without removing the old path immediately.

**Done when:** a feature flag selects old or world-resident mode and contract tests pass.

### VW-015: Add Mistral reasoning adapter

Generate bounded prompt/context, require validated JSON output, implement timeout/cancellation, and record model/prompt versions.

**Done when:** evaluation cases pass and malformed output safely becomes no reaction/error.

### VW-016: Connect existing Creature Server dialog API

Translate performance intents to inline dialog turns, pass the active parent trace through Creature Server’s existing supported mechanism exactly as the current `creature-agent` does, propagate interaction/correlation IDs, and ingest job outcome.

**Done when:** one real Beaky performance is visible end-to-end in Viewer and Honeycomb as a single distributed trace spanning the source/simulator, agent mind, Mistral request, Creature Server request, and server processing; asynchronous completion is continued or span-linked without losing the interaction’s causal identity.

### VW-017: Scaffold macOS bridge and outbox

Start both parts of the Information Bridge: the background `creature-scribed` daemon and the Creature Scribe SwiftUI application. Define their IPC/configuration boundary; source authorization and health model; Keychain-backed secrets; privacy and retention policy; durable processing ledger; retryable outbound event queue; and a redacted event inspector. Add a fake source and deterministic fake `PrivateInformationDistiller`, and propagate trace context with the resulting synthetic event.

**Done when:** the SwiftUI application can close while the daemon continues processing; one synthetic private-source item is visible as it moves through classification, validation, outbox, retry, delivery, and trace states; it safely reaches the Linux simulator after an offline interval; and neither logs nor UI diagnostics expose private source content by default.

### VW-018: Implement EventKit ingestion

Add calendar selection, source checkpoints, initial import, incremental event upsert/cancel, timezone and all-day semantics, privacy filtering, and trace-propagated delivery through the bridge outbox. Emit schedule facts; leave the full reminder behavior to `VW-027`.

**Done when:** a selected calendar’s create, update, reschedule, and cancellation cases produce the correct idempotent WorldEvents, survive bridge restart, and appear in Creature World and World Viewer without copying private calendar notes unnecessarily.

### VW-019: Implement weather fusion

Add WeatherKit forecast events, HA weather-station facts, fusion policy, and material-change detection.

**Done when:** viewer explains the source of each current/forecast property.

### VW-020: Spike Mail integration

Time-box MailKit extension viability; document permissions, arrival coverage, message data access, and fallback recommendation. The selected acquisition path must feed the shared local Apple Intelligence distillation pipeline. It must not implement Mail-specific world logic or turn Creature World into a mailbox mirror.

**Done when:** choose MailKit, local rule/endpoint, automation, or local-store adapter based on a working prototype; a sanitized message passes through the fake or real shared distiller into a validated WorldEvent; and no raw body is delivered to the simulator.

### VW-021: Teach the world what arrived

Implement the merchant-neutral commerce lifecycle that lets Beaky recognize what arrived: local classification/extraction fixtures, order and fulfillment schemas, provisional identity/merge behavior, correlation, status transitions, and vague-update preservation tests. Include multiple merchants, an unseen merchant handled by the generic extractor, duplicate order numbers belonging to different merchants, multi-shipment orders, pickup, cancellation, return, and refund cases. Keep any Amazon-specific extractor as an optional profile outside the canonical model.

**Done when:** sample servo and Raspberry Pi heat-sink orders retain their rich item identity through vague shipped/delivered updates; the same pipeline handles a structurally different unknown merchant; no canonical schema or simulator reducer branches on Amazon; a delivered-servo situation produces a grounded Beaky percept without exposing the source mail; and World Viewer can explain the path from original item evidence to Beaky’s consideration. Character evaluation should reward a specific, playful, grounded response such as “Hey April, I think the servos you ordered are here!” without requiring that exact sentence.

### VW-022: Spike Messages integration

Time-box supported/local database access, permissions, schema, incremental checkpoints, and retention/privacy behavior. Route opt-in messages through the same classifier/extractor and Contacts identity resolver used for Mail rather than creating a Messages-only semantic model. Represent permission loss and source schema changes as visible degraded health states.

**Done when:** a new opt-in message becomes a short-lived expected-arrival event without exporting raw text.

### VW-023: Add the WorldMCP Streamable HTTP adapter

Create an independently deployable `WorldMCP` target using the current MCP Streamable HTTP transport. Wrap the simulator’s authorized query/application services with the initial read-only resources and tools from Section 4.13. Start stateless; add authentication/authorization, Origin validation, safe binding defaults, concurrency/result limits, pagination, cancellation, and OTel propagation. Do not enable the legacy `/sse` plus `/message` transport by default.

**Done when:** an MCP client can inspect an entity, query a bounded event window, and retrieve a Why? provenance graph; responses match the Viewer API; unauthorized perspective access and mutating tools are denied; reconnects do not affect world state; and transport/security tests pass.

### VW-024: Extend Debian packaging to every Linux product

Inspect and extend the existing `debian/` metadata, `Dockerfile.debian`, `build_deb.sh`, `clean_deb.sh`, and `.github/workflows/build-deb.yml`. Create a product/architecture matrix that emits a separately installable `.deb` for every separately deployed Linux executable. Preserve the Debian Trixie, Swiftly-pinned toolchain, release/static Swift runtime, `dpkg-buildpackage`, amd64, arm64, and per-architecture artifact conventions already used by the repository. Add clean-container install, linkage, offline CLI, service-file, upgrade, uninstall, and persistent-data-preservation tests.

**Done when:** CI fails for an unclassified Linux executable; every classified deployable product emits an amd64 and arm64 `.deb`; all packages install and smoke-test on clean Debian Trixie environments; and artifacts use unambiguous package/version/architecture names.

### VW-025: Implement the Apple Intelligence distiller

Implement `PrivateInformationDistiller` with the macOS 27 Apple Intelligence/Foundation Models APIs behind a provider boundary. Use a cheap first-stage relevance/domain classifier followed by typed structured extraction only for relevant items. Version prompts and output schemas; validate every result deterministically; retain bounded evidence references rather than raw text; record model, prompt, schema, and OS versions; and expose model unavailable, declined, malformed, and validation-failed states. Keep the deterministic fake implementation for tests. Do not silently fall back to a remote model with raw Mail or Messages content.

**Done when:** sanitized Calendar, Mail, and Messages fixtures produce validated domain objects and WorldEvents; irrelevant items stop before extraction; fabricated/invalid fields are rejected or quarantined; model/OS changes can be evaluated against a golden corpus; and private source text never crosses the bridge boundary.

### VW-026: Implement bridge identity, privacy, and review workflow

Use Contacts to resolve local sender/recipient identifiers into stable person references and relationship labels without copying the address book to Linux. Add source/calendar/conversation allowlists, retention controls, redacted previews, quarantine/review, correction and supersession, retry/discard controls, and links from a distilled result to its WorldEvent and Honeycomb trace. Store only the minimum local evidence required to explain or correct a result.

**Done when:** April can see why an item was considered, approve or correct an uncertain extraction, retry delivery, follow its trace, and expire the underlying local source material; the simulator receives a correction/supersession event rather than a history rewrite.

### VW-027: Complete the proactive calendar vertical slice

Connect EventKit ingestion, timezone-aware simulation time, durable `WorldClock` timers, presence, interest routing, agent repetition guards, and Creature Server performance. Cover all-day events, timezone changes, cancellation, rescheduling, late ingestion, acknowledgement, and simulator restart. Preserve one distributed trace or explicit span links from bridge observation through performance completion.

**Done when:** a controlled church/departure scenario results in exactly one contextually appropriate reminder, is suppressed when it is no longer useful, survives restart without duplication, and can be explained end-to-end in World Viewer and Honeycomb.

### VW-028: Build Beaky Communicator and policy-gated remote delivery

Build Beaky Communicator as one SwiftUI product for macOS and iOS with shared conversation state,
networking, offline queue, and views. Use the `PersonUtterance`, `CharacterUtteranceIntent`, and
delivery contracts from `VW-030`; do not create app-only cognition or message types. Build the
isolated `creature-communicator-gateway` with secure pairing, proxy-protected off-LAN synchronization, APNs
registration/token rotation, an idempotent notification outbox, preview/private payload modes,
actions, replies, renewable per-device foreground leases, and privacy-safe trace correlation. A
foreground client heartbeats its lease and releases it on backgrounding when possible; expiry is
authoritative because lifecycle callbacks are not guaranteed. Any live paired-device lease
suppresses a redundant push. Foreground attention includes lock state and, on macOS, configurable
local idle time; raw input activity never leaves the device. Package the gateway independently for
Debian Trixie on amd64 and arm64 under `/bin`.

Test full-history pagination, foreground incremental catch-up, multiple simultaneous clients,
lease renewal/release/expiry, abrupt client loss, iOS/macOS lock transitions, macOS
active/inactive/idle/hidden/minimized/windowless transitions, confirmed-away versus
at-home/uncertain presence, notification authorization changes,
quiet hours, urgency, topic allowlist, TTL expiry, retry, duplicate intents, APNs rejection,
device-token rotation/revocation, offline app actions, duplicate action submission, preview
redaction, unauthorized mobile requests, and the distinction between APNs acceptance and user
interaction. Use a fake APNs provider for deterministic tests and Apple’s Push Notification
Console/development environment for an explicitly enabled device smoke test.

**Done when:** April can carry on one ordered Beaky conversation from macOS and iOS; home responses
are represented as physically spoken without duplicate alerts, away responses synchronize to her
paired devices, a foreground device sees new turns without reopening the app, no push is sent while
any paired client holds a live foreground lease, uncertain presence uses the private app route, and
offline/retried turns remain idempotent. The exchange becomes world history without leaking device
tokens, signing credentials, utterance text, or unrelated private context into telemetry.

### VW-029: Expose the Creature World JSON API and live delta stream

Add the Hummingbird application and query boundary over the authoritative `World` actor and its
repositories. Implement the initial routes required by adapters and World Viewer: bounded single
and batch event ingress, ordered event history after a sequence, current-fact queries, timer
queries, and an ordered live delta stream with reconnect and resnapshot semantics. Reuse
application services across HTTP and future MCP adapters; transport handlers must not bypass them
to query MongoDB directly. Keep entity, character perspective, memory, and complete Why?
provenance routes with the issues that introduce their backing read models.

Preserve the versioned snake-case JSON contracts and idempotent acceptance dispositions. Enforce
body, batch, concurrency, duration, pagination, and stream-buffer limits; translate overload and
lag into explicit responses. Under the trusted-LAN architecture, keep health, event, and world-state
routes open; firewalls and the external ingress proxy own access control outside the LAN. Propagate
W3C trace context and never attach event payloads or credentials to telemetry.

**Done when:** a black-box test starts the Linux service, submits a synthetic event, observes its
ordered live delta, reads it back by sequence, verifies duplicate submission is idempotent, and
reconnects from the last observed sequence without a gap; the accepted event survives a process
restart; malformed, oversized, overloaded, and lagging requests fail explicitly; and the same
contract tests pass with Swift 6.3.3 on Linux.

### VW-030: Define the unified April-utterance and Beaky-delivery pipeline

Add versioned `PersonUtterance`, `CharacterUtteranceIntent`, conversation item, delivery decision,
and delivery outcome contracts with checked-in snake-case JSON fixtures. Implement one utterance
ingress service used by adapters for Beaky Communicator composition/replies, the development
Wizard Mode, and future STT. Preserve modality, source, timing, confidence, place evidence, provenance,
and trace context while producing the same addressed Beaky percept/context path for equivalent
meaning. Support both directions: Beaky may initiate or answer a turn, and April may answer a
specific Beaky turn in the same conversation.

Implement a deterministic delivery router that evaluates fresh authoritative presence after a
character utterance exists. Confidently home and physically audible chooses Creature Server;
confidently away chooses durable Communicator delivery; stale or uncertain presence chooses the
private Communicator route. The character may author content, urgency, expiry, and reasons but
cannot select a transport. Persist stable utterance, response, and delivery-attempt identities so
ordering, retry, restart, reconnect, and a concurrent presence transition cannot duplicate a turn
or deliver it through both routes. Persist the character's canonical conversation item before
either delivery sink so physically spoken and Communicator turns remain one shared history.

**Done when:** deterministic tests submit equivalent semantic fixtures through Communicator,
Wizard Mode, and fake-STT adapters and prove the same Beaky percept/context path; Beaky-initiated and
April-initiated turns remain linked; the same fake character turn routes once to physical delivery
when home, app delivery when away, and private app delivery when presence is stale; retries and
presence transitions remain idempotent; schemas round-trip on macOS and Swift 6.3.3 Linux; and
security/OTel tests prove bounded conversation records, the ingress authorization boundary, and
the absence of conversation content, credentials, source identifiers, or trace baggage from
telemetry.

---

## 18. Explicit non-goals for the first implementation

- No rewrite of Creature Server’s timing, animation, ElevenLabs, or controller pipeline.
- No merger of World Viewer and Creature Console.
- No persistent state or cognition in Creature Controllers.
- No protobuf/gRPC requirement.
- No high-frequency physics or exact spatial simulation.
- No omniscient agent database access.
- No raw full-mailbox or Messages archive copied to Linux.
- No cloud LLM requirement for routine operation.
- No facial recognition requirement for the first presence system.
- No generic mass-market multi-user product, tenant system, or App Store design.
- No guarantee that every event produces a character response.
- No immediate live improvised multi-character turn-taking.
- No automatic deletion of conflicting historical evidence.
- No timeline replay that mutates the production world.
- No continuous audio archive.
- No raw APNs tool for Mistral, arbitrary mobile recipients, direct iOS access to MongoDB, or public omniscient world API; the Communicator pathway is policy-gated and initially limited to April’s paired devices.
- No replacement of the Viewer’s ordered state replication or adapter event-ingress APIs with MCP.
- No legacy MCP HTTP+SSE transport unless required for a named client during migration.

---

## 19. Future audio perception and `creature-listener`

Revisit `creature-listener` as a perception adapter, not the component that makes Beaky respond. Wake-word detection should become one signal that speech may be directed at a character, not the gate around the whole cognition loop.

Future pipeline:

```text
room microphones
  -> continuous local STT
  -> room/speaker/source/confidence metadata
  -> TV/radio/overlap filtering
  -> local semantic relevance extraction
  -> speech observations and WorldEvents
  -> world perception and interest management
  -> character agents
```

Potential observations include speech detected, likely speaker, likely addressee, transcript fragment, room, confidence, and conversation context. A character may react without hearing its wake word if the speech is relevant and perceptible.

Retention should be aggressive:

- raw audio buffer: seconds;
- raw transcript: minutes or hours as needed for local processing;
- extracted meaningful facts/events: retained according to normal world/memory policy.

Challenges to solve later include source attribution, overlapping speech, television contamination, acoustic reach, false positives, and deciding what deserves to enter the world. All processing should remain local by default. This future system replaces the old wake-word-centric `creature-listener` design rather than reviving it unchanged.

---

## 20. Open decisions and implementation cautions

Resolve these with short spikes or ADRs rather than blocking Phase 1:

- exact Swift HTTP/WebSocket framework on Linux;
- lowercase UUID generation/normalization policy and atomic world sequence allocation;
- Mongo transaction strategy versus idempotent multi-document writes;
- exact authenticated remote-gateway pairing and credential-rotation design, while LAN service APIs remain open;
- WeatherKit availability/entitlement details on the M1 iMac;
- exact MailKit arrival/content limitations in the target OS;
- exact Messages local-store access and TCC requirements;
- route/travel-time source after the configured-duration first version;
- whether `creature-agent` is one process per character or one host process with isolated character sessions;
- how Creature Server accepts/returns trace and interaction IDs;
- semantic retrieval technology for memories after deterministic metadata retrieval is proven.
- whether the first app-to-home return path uses the existing private VPN/Tailscale-style network or a separately hosted narrow relay;
- exact device-pairing ceremony, credential rotation, notification privacy default, and APNs key operational model.

Avoid these early traps:

- letting adapters emit vague untyped blobs;
- putting source-specific topic/entity names in the simulator;
- blocking the World actor on database, network, or model calls;
- using confidence as a substitute for provenance;
- storing prompt-size snapshots without retention limits;
- allowing the viewer to silently edit production truth;
- trying to solve memory consolidation before reliable events/facts/perspectives exist;
- making Mistral responsible for deterministic timer or lifecycle logic;
- generating character prose inside world triggers;
- treating “no reaction” as an error.
- allowing Mistral to select device tokens, bypass notification policy, or invoke APNs/mobile APIs directly.

---

## 21. Definitions of the first application milestones

The first milestones deliberately prioritize relationship before breadth. First prove that April and
Beaky can share a conversation; then make it live through Beaky’s body and Communicator; then widen
the world’s private context and explainability.

### Milestone A — one conversation exists

April can submit the same semantic utterance through Beaky Communicator, Wizard Mode,
or fake future STT and Beaky receives it through one percept/context path. Beaky can initiate or
answer a turn; April can reply to that exact turn. A fake character response routes exactly once to
physical or Communicator delivery based on deterministic presence. This is the exit from Phase 2.

### Milestone B — Beaky can hear and answer April

April types to Beaky from macOS or iOS; Beaky’s real agent answers in the same conversation. When
April is home and audible the physical bird speaks; when she is away or presence is uncertain the
turn appears durably in Beaky Communicator, with private notification behavior where appropriate.
April’s reply becomes Beaky’s next percept without duplicate turns across retry or restart. This is
the exit from Phase 3.

### Milestone C — the world becomes visible and understands something private

Creature Scribe plus `creature-scribed` runs on the iMac and World Viewer runs on the laptop. A
synthetic private-source item moves through the bridge’s fake local distiller and durable outbox,
becomes an authoritative fact, and appears with Why? provenance in Viewer. Then macOS 27 Apple
Intelligence locally distills one opted-in Calendar, Mail, or Messages item without exporting raw
content. These are the exits from Phases 4 and 5.

The proactive calendar behavior then builds on the conversation that already works: time and
presence combine to make Beaky notice April should be on the road, and the existing delivery route
puts her voice where April can hear it.

Weather fusion, sophisticated long-term memory, and continuous audio remain later work. Mail and
Messages are not deferred ideas; their acquisition spikes and shared Apple Intelligence pipeline
begin after the relationship spine is live and observable.

That is the architecture in one line:

> **The world happens. The agents notice. The server performs. The controllers obey.**

And the reason for building it remains:

> **Make Beaky really be April’s familiar. Make the house feel alive.**
