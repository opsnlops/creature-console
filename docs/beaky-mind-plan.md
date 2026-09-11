# Beaky's Mind — Slice B Implementation Plan

**Issues:** [#105](https://github.com/opsnlops/creature-console/issues/105) (VW-014, agent input
boundary), [#106](https://github.com/opsnlops/creature-console/issues/106) (VW-015, reasoning
adapter). Tracked by #90.
**Roadmap:** Phase 3, Milestone B.
**Product:** `creature-agent` `2.54.1` → `2.55.0` (with `creature-cli`/`creature-mqtt` in lockstep
per the established Debian source-package convention).

## The magic this unlocks

April types "Hello Beaky" on her phone. A few seconds later Beaky answers — **in her own words**,
having read what April said before, remembering what she herself said last. Tonight's "Hello
Claude → Beaky → Fun!" round trip on production used a human at a keyboard for Beaky's half. This
slice removes the human. After it, nothing sits between April and Beaky but the mind.

## Where things stand

- Creature World `0.2.0` accepts `CharacterUtteranceIntent` at
  `POST /world/v1/conversations/{id}/responses` and pushes the canonical item live (#134/#135).
- April's every turn is already a `conversation.person_utterance` WorldEvent on
  `/world/v1/stream`, carrying a `PersonUtterancePercept` addressed to `character:beaky` with
  `prior_conversation_items` — both authors, in order. That **is** the percept boundary VW-014
  asks for; nothing new has to be invented on the World side.
- `/world/v1/stream` resume semantics (`Last-Event-ID`, replay, `resnapshot_required`) are proven
  black-box on Linux by #139.
- `creature-agent` is still the MQTT-topic parrot. Its good parts — `LocalLLMClient` (llama-server
  at `10.69.66.4:1234`, OpenAI-compatible, streaming, `<think>` stripping), `TextSanitizer`,
  `LocalLLMHealthCheck`, OTel bootstrap, YAML config, Debian packaging — are exactly what the mind
  needs. Its MQTT parts stay untouched (`creature-mqtt` and the MQTT mode keep working).

## Design

```text
creature-agent run   (config: mode: world)
  │
  ├─ WorldPerceptSubscriber
  │    GET /world/v1/stream  (Last-Event-ID = durable cursor; snapshot when none)
  │    keep only deltas whose event.type == conversation.person_utterance
  │      and payload.character_id == configured character
  │    reconnect with backoff; resnapshot_required → reconnect without cursor, log loudly
  │
  ├─ CharacterMind   (one consideration at a time, in world order)
  │    guardrails first (deterministic, no model):
  │      stale (occurred_at older than maximumReplyAge)      → silence: "stale"
  │      addressed to someone else / not April              → silence: "not_addressed"
  │    prompt = persona system prompt + contract
  │           + prior_conversation_items as user/assistant turns (bounded, newest N)
  │           + the current utterance
  │    LocalLLMClient.respond(messages:)  with timeout + cancellation
  │    validate: strip <think>, TextSanitizer, "[silence]" → silence: "chose_silence",
  │              empty → silence: "empty_response", > 4096 scalars → truncate at sentence
  │    → CharacterUtteranceIntent { response_id = uuid5(consideration_id),
  │                                 in_response_to_utterance_id, trace = percept trace }
  │
  ├─ WorldResponder
  │    POST /world/v1/conversations/{id}/responses (traceparent propagated)
  │      202 accepted / 200 duplicate  → advance cursor
  │      400 invalid_request (identity conflict) → "already answered differently"; log, advance
  │      5xx / transport                        → retry with backoff, cursor unchanged
  │    silence → log + metric + advance cursor (a recorded decision, not an error)
  │
  └─ WorldAgentCursor   (state directory file; written only after a decision is durable)
```

### Decisions

- **One conversational reality.** The prompt context comes from the percept's
  `prior_conversation_items` — the canonical history with both authors — never from the agent's
  MQTT-mode `ConversationHistory`. Beaky's own earlier turns therefore appear as `assistant`
  turns; she can't contradict herself without noticing.
- **Idempotent by construction.** `response_id` is UUIDv5 of the `consideration_id`, and the
  cursor advances only after World has accepted (or reported duplicate). A crash between POST and
  cursor write replays the percept; the model may phrase differently, World refuses the second
  identity (`conflictingConversationIdentity` → 400), and the agent treats that as "already
  answered" and moves on. One wasted model call, never two Beaky turns.
- **Silence is a recorded decision.** Every consideration ends in exactly one of: a posted turn,
  or a silence with a `suppression_reason` in the log and a `creature_agent.considerations`
  metric dimension. Nothing is "dropped".
- **Start from now.** With no cursor, the subscriber starts at the snapshot's latest sequence.
  Beaky does not wake up and answer three days of backlog. With a cursor, missed turns are
  replayed; `maximumReplyAge` (default 1 h) turns very old ones into recorded `stale` silences.
- **The model authors words, never transport.** The intent has no channel. World's router
  decides Communicator vs. room from presence (unknown → private Communicator today).
- **Structured output, minimally.** VW-015's full validated-JSON decision is deferred until the
  local model's JSON reliability is measured; for this slice the contract is plain text with one
  reserved token (`[silence]`) and deterministic validation. `prompt_version` and `llm.model` are
  recorded on the consideration span so evaluations stay comparable.
- **Trace continuity.** The percept's W3C context (from the app → gateway → World) is the remote
  parent of `agent.consider`; `llm.mistral.generate` and the World POST are its children, and the
  posted intent carries the new context. One Honeycomb trace from April's tap to Beaky's turn.
- **No World change.** Slice B is agent-only. Recording decisions in a World
  `agent_considerations` collection (for the Viewer's "why did she stay quiet?") is VW-008/VW-011.
- **MQTT mode is untouched.** `mode: mqtt` (the default) runs exactly today's code. `mode: world`
  needs `worldUrl` and `characterEntityId`; `areas` becomes optional.

### Configuration (YAML additions)

| Key | Default | Meaning |
| --- | --- | --- |
| `mode` | `mqtt` | `mqtt` or `world` |
| `worldUrl` | `http://127.0.0.1:8001/world/v1` | Creature World API |
| `characterEntityId` | `character:beaky` | which character this process is |
| `personEntityId` | `person:april` | whose utterances to answer (first version) |
| `stateDirectory` | `/var/lib/creature-agent` | cursor file location (`StateDirectory=` in the unit) |
| `maximumReplyAge` | `1h` | older percepts become `stale` silences |
| `maximumContextTurns` | `20` | newest prior items sent to the model |
| `llmTimeoutSeconds` | `60` | model call deadline |

### Files

| File | Purpose |
| --- | --- |
| `Sources/CreatureAgent/World/WorldPerceptSubscriber.swift` | SSE client, filtering, resume, backoff |
| `Sources/CreatureAgent/World/CharacterMind.swift` | guardrails, prompt, validation, decision |
| `Sources/CreatureAgent/World/WorldResponder.swift` | POST intent, outcome handling |
| `Sources/CreatureAgent/World/WorldAgentCursor.swift` | durable cursor file |
| `Sources/CreatureAgent/World/runWorldMode.swift` | wiring under `run` when `mode: world` |
| `Sources/CreatureAgent/LocalLLMClient.swift` | add `respond(messages:)`; existing API unchanged |
| `Sources/CreatureAgent/AgentConfig.swift` | new keys; `areas` optional in world mode |
| `Package.swift` | `creature-agent` gains `WorldCore`, `AsyncHTTPClient` |
| `debian/creature-agent.service`, `.yaml` | `StateDirectory=creature-agent`, sample world config |

### Tests (`CreatureAgentTests`, deterministic, no network)

- Subscriber: snapshot start, delta filtering by type and character, `Last-Event-ID` on
  reconnect, `resnapshot_required` handling, backoff — against an in-process Hummingbird stub.
- Mind: prior items map to roles in order and are bounded; stale → silence; `[silence]` →
  silence; empty/whitespace → silence; sanitizer applied; over-length truncated at a sentence;
  response ID deterministic for a consideration; trace carried from percept to intent.
- Responder: 202/200 advance the cursor; 400 identity conflict advances with a warning; 503
  retries without advancing; the cursor is never written before acceptance.
- Restart: a crash after POST replays the percept and produces no second turn.
- Linux: `creature-agent` builds in the 6.3.3 container (`./build_debs.sh --arch amd64`).

## Exit

April types on her phone; within a few seconds a Beaky bubble appears with words the local model
wrote from the conversation so far; her next message reaches the mind with Beaky's reply in its
context; restarting `creature-agent` mid-conversation never produces a duplicate turn; a
message the model declines is a logged silence, not an error; and one Honeycomb trace spans
app → gateway → World → agent → model → World.

## The stage that matters most — a correction from April

> "Most of these responses are actually said out loud. We're building animations that get sent to
> the ad-hoc pipeline on the server. The chat app is for use when I'm not at home (and as a way to
> tell Beaky things before the STT pipeline is working)."

So this slice is the *away* path and the input path, and it proves the mind. The normal case is
April at home and Beaky answering with her body and voice. That reshapes what comes immediately
after, and it is not a "later":

1. **VW-016 must keep sentence streaming.** `LocalLLMClient.respondStreaming` already feeds
   Creature Server's ad-hoc session sentence by sentence (the 15.5 s → ~2 s first-words work).
   World's router decides the stage *after* an intent exists, which would force full-text-then-
   speak. The physical route therefore needs the mind to learn the stage *before* generating —
   ask the world where April can hear Beaky, stream to Creature Server if the answer is the room,
   then record the canonical turn and a `performed` outcome (with the job ID) in the world. The
   router's idempotency contract still holds through the same `response_id`.
2. **An `assumed` presence until Home Assistant exists.** `assumed` is a first-class epistemic
   type in the design. A configured assumption ("April is home and audible") is an honest way to
   put Beaky on the physical stage now; the decision records that it was assumed, and VW-006/
   VW-013 replace the assumption with evidence.
3. **Every turn still enters the shared history**, so Communicator shows what Beaky said aloud
   and April can answer it from her phone.

## After this

- **Each character's personality.** Today Beaky's voice is one `llmSystemPrompt` string plus a
  fixed conversation contract. The design wants residents with interests, aversions, relationship
  attitudes, running jokes, and their own memories (§2, §4.10, §8). That is a phase of its own:
  a versioned per-character personality definition, memories retrieved from the world, and an
  experience rubric per character (§16.6) — with personality living in the agent, never in
  triggers or the world.

- VW-016 (#107): the physical-speech sink — `LocalLLMClient.respondStreaming` already streams
  sentences to Creature Server's ad-hoc session; presence decides when that stage is chosen.
- VW-006/VW-013: real presence so the router can put Beaky's voice in the room.
- VW-008/VW-011: decisions recorded in World for the Viewer's "Why?".
