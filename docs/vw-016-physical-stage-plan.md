# Beaky's Voice in the Room — VW-016 and Assumed Presence

**Issue:** [#107](https://github.com/opsnlops/creature-console/issues/107) (VW-016). Assumed
presence is scoped here too; VW-006/VW-013 later replace the assumption with evidence.
**Design:** [`beakys-world.md`](beakys-world.md) §17 (Creature Server integration), §4.4
(`assumed` epistemic type), and the correction in
[`beaky-mind-plan.md`](beaky-mind-plan.md#the-stage-that-matters-most--a-correction-from-april).
**Products:** Creature World `0.3.0` → `0.4.0`; `creature-agent` `2.55.4` → `2.56.0`; World
Viewer shows the new decisions.

## The moment

April is home. She says something to Beaky (typed, until STT exists). About two seconds later
Beaky *answers out loud*, in her body, sentence by sentence while the model is still thinking —
the same ~2 s first-words feel the MQTT agent has today. The turn is also in the shared history,
so the Communicator shows what Beaky said and April can answer from her phone later. In World
Viewer the delivery chip beneath the turn reads **physical_speech · home_and_audible ·
home 100% · audible · performed**, and the Mundane view shows the presence was `assumed`.

When she is away (or the assumption is switched off) nothing changes from today: the turn goes
to the Communicator with `presence_uncertain` or `confidently_away`.

## Why the mind performs and the world decides

April: "Most of these responses are actually said out loud… the chat app is for use when I'm not
at home." The World's router today decides the stage *after* an intent with full text exists,
which would force full-text-then-speak and throw away the streaming work. So:

- **The world still decides.** Presence, rules, the recorded decision, the idempotency by
  `response_id`, the canonical item, the outcome — all in Creature World, all visible in the
  Viewer. The world never authors words.
- **The mind asks first, then performs.** Before generating, the mind asks the world for the
  stage for the `response_id` it is about to use. If the answer is the room, it streams sentences
  to Creature Server's ad-hoc session as they are produced (the existing `respondStreaming` +
  `startStreamingAdHocSpeech / addStreamingAdHocText / finishStreamingAdHocSpeech` path), then
  records the finished turn and the performance outcome in the world in one call. If the answer
  is the Communicator, today's path is unchanged.
- **Every turn enters the shared history** regardless of route.

This is exactly §17's "translate performance intents to inline dialog turns, pass the active
parent trace through Creature Server's existing mechanism exactly as the current `creature-agent`
does, propagate correlation IDs, and ingest job outcome" — with the intent flowing through the
world, not around it.

## Creature World `0.4.0`

### Assumed presence

`AssumedPresenceProvider` replaces `UnknownPresenceProvider` when configured; otherwise the
world keeps reporting `unknown`. Configuration in `/etc/creature-world.json`:

```json
"presence": {
  "assumed": {
    "person:april": { "state": "home", "physically_audible": true, "confidence": 0.9 }
  }
}
```

`PersonPresence` gains `basis: EpistemicType` (`assumed` here; `inferred` for the unknown
provider; decodes as `inferred` when absent so existing delivery rows still load). The router's
decision therefore records *that the world assumed*, and the Viewer says so. Turning the
assumption off (or removing the block) restores today's Communicator-only behaviour without a
code change. Real presence (VW-006/VW-013) later swaps the provider and nothing downstream moves.

### Stage decision: `POST /world/v1/conversations/{conversation_id}/stage`

Body: `{ "response_id", "character_id", "recipient_id" }`. The router reads fresh presence, makes
the same `CharacterDeliveryDecision` it would make for an intent, and **persists it** in a new
`character_stage_decisions` collection keyed by `response_id` with a TTL (default 5 minutes;
migration v5 adds the collection and index). Repeating the call for the same `response_id`
returns the stored decision — a replayed consideration after a crash asks the same question and
gets the same answer. If a delivery for that `response_id` already has an outcome, the response
says `already_delivered` with the record so the mind does not speak twice.

Response: `{ "disposition": "decided" | "already_delivered", "decision", "delivery"? }`.

### Performed turn: `POST /world/v1/conversations/{conversation_id}/performances`

Body: `{ "intent": CharacterUtteranceIntent, "attempt_id", "outcome": { "state", "provider_reference"?, "error_code"? } }`.
The router requires a stage decision for the `response_id` whose `attempt_id` matches (400
otherwise — a performance the world never staged is refused), persists the canonical item,
decision, and outcome atomically through the existing `character_deliveries` repository, publishes
the item to conversation subscribers (so the Communicator shows what she said aloud), and returns
the same `CharacterDeliveryResult` shape as `/responses`. Idempotent by `response_id`.

### `POST …/responses` honours a stage decision

If a stage decision exists for the intent's `response_id`, the router reuses it instead of
reading presence again, so a mind that asked and was told "Communicator" is routed exactly as it
was told. Hand-cast turns and older minds see no change.

### Router and sinks

`CharacterDeliveryRouter` gains `stage(_:)` and `recordPerformance(_:)`; `route(_:)` consults
stage decisions. `NotConnectedPhysicalSpeechSink` stays for the case where a *non-staged* intent
arrives while presence says home — the world never speaks on its own, so it records `failed /
physical_speech_not_connected` as today. (Making the world itself a Creature Server client is a
possible later step for scheduled or unprompted speech; not this slice.)

## `creature-agent 2.56.0` (world mode)

- Config: `stage: physical | communicator_only` (default `physical`); the existing `creatureId`
  and Creature Server `--host/--port` are now used in world mode. `communicator_only` is the
  escape hatch that reproduces `2.55` behaviour.
- `CharacterMind.consider` becomes: guardrails → `stage` (via `WorldStage` protocol on the
  responder) → if physical: `PhysicalStage.perform(sentences:)` (protocol over the Creature
  Server client: start session lazily on the first speakable sentence, add each sanitized
  sentence, finish; returns the animation/job ID) while `respondStreaming(messages:)` runs →
  `performances` with the full text and `performed`/`failed`. If communicator: today's
  `respond` + `/responses`.
- Per-sentence validation: the first sentence decides silence (`[silence]` → no session, silence
  recorded as today); speaker-label stripping (#154) on the first sentence; the speech sanitizer
  on every sentence; the sentence-bounded length limit stops the stream. The recorded text is the
  concatenation of what was actually sent to the server, so history matches what she said.
- Failure modes are honest: Creature Server unreachable or `start` fails → she does not fall back
  to speaking later; the turn is still recorded with `failed / <error_code>` and lands in the
  Communicator so April sees it. Crash between speaking and recording → the replay asks the
  stage, gets `already_delivered` only if the record exists; otherwise she may say it again
  (documented, rare, and visible in the Viewer as two attempts).
- Tracing: the Creature Server client already injects `traceparent` from the current span, so
  the ad-hoc session joins the `agent.turn` span; new spans `agent.stage`, `creature.server.perform`.
- **Production:** with `stage: physical` and the assumption on, `2.56.0` can finally speak — the
  precondition for replacing the MQTT agent on prod (a separate decision; MQTT-mode reactions to
  house events are not in this slice).

## World Viewer

Delivery chip shows the presence basis (`assumed`/`inferred`/…) and the outcome
`provider_reference` (animation ID) on hover; nothing else changes.

## Tests

- WorldCore: `PersonPresence.basis` round-trip and default; router `stage` idempotency,
  `already_delivered`, `recordPerformance` refusing an unstaged attempt, `route` honouring a stage
  decision.
- CreatureWorld: `AssumedPresenceProvider` from config; `/stage` and `/performances` HTTP tests;
  Mongo stage-decision repository (TTL index, atomic prepare) in the persistence tests; black-box
  test: stage → performances → item visible on the conversation stream.
- CreatureAgent: `CharacterMindTests` with a fake `PhysicalStage` — sentences streamed in order,
  lazy session start, silence never opens a session, sanitizer per sentence, length limit,
  server failure recorded as `failed`; `WorldMindServiceTests` stub World gains the two routes.
- Manuals: `creature-world-manual.md` (routes, presence config), `creature-agent-manual.md`
  (`stage`, Creature Server in world mode), `world-viewer-manual.md` (chip), `beakys-world.md` §0.

## Exit

On fuzzball with `presence.assumed` for April: type to Beaky from the phone, hear her answer
through the creature within ~2 s of the first sentence, see the same words appear in the
Communicator and in the Viewer with `physical_speech · home_and_audible · performed`, and one
Honeycomb trace spanning phone → gateway → World → `agent.turn` → Mistral → Creature Server →
World. Remove the assumption: the next turn goes back to the Communicator, and the Viewer shows
why.
