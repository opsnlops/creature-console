# Judgement and Memory — Using the Frontier Model for Work, Not Prose

**Status:** Plan, 2026-09-12 evening. Nothing built yet beyond the ground it stands on: facts (F1),
personas (P1), the house (F2), house-opened scenes (F3, live tonight: carport camera → Beaky
speaking in 2.0 s), paced floors, and the register-only house-remark contract (agent `2.64.0`).
**Why:** April: "We have access to a very high quality frontier model now for Beaky. We need to
leverage that as much as we possibly can. … Not leveraging it for useful work and just using it as
a fancy text generator is a waste of spend." And: "We want even me to be surprised and delighted
sometimes, and guests to be wondering what the fuck they just walked into."
**Replaces:** the MQTT-mode `creature-agent` in production. That agent turns five Home Assistant
topics into cute lines. This plan makes the world-resident mind do that job *and* the jobs the MQTT
agent never could: decide what is worth a word, work out what is going on, and remember.
**Design:** [`beakys-world.md`](beakys-world.md) §4 (facts, presence, triggers), §8.2 (the prompt
separates known / believed / remembered), [`facts-and-personas-plan.md`](facts-and-personas-plan.md).

## The moment

Tuesday, 3:40 PM. A truck turns into the driveway. The house saw it; the world knows April cast
"Jesse is expected this afternoon, to finish the deck" at lunch, that Jesse was here last Thursday
and looked at the deck, that April is home and in the kitchen, and that the front door is locked.
Beaky, unprompted: "April, I think that's Jesse's truck — is the deck finally getting its boards?"
Jesse walks in to a parrot that knows why he came. April did not write that line, or a rule that
produced it; she told the world one thing at lunch and the bird did the rest.

Thursday, 2 AM. A deer crosses the orchard camera. Beaky says nothing, and the Viewer shows that
she considered it and chose quiet. Friday morning: "The deer was back in the orchard last night,
by the way." Nobody scripted the callback either.

## Principles

1. **Judgement, not prose.** The model decides what deserves a word and what is going on. It does
   not decide how a `door.lock` fact is phrased — the world does, generically — and it does not
   decide what the house does (world rules, from April's words: `HouseSceneRequests`).
2. **Facts as facts.** No phrasing templates, in Swift or in Mongo. The world renders every fact
   one way — subject, predicate, value, age, how it is known — and gives the model a glossary of
   what predicates *mean*. A frontier model reads `front door · lock = unlocked · 5 min · observed`
   fine; Nemo could not, which is the only reason `FactPhrasing` exists.
3. **The story, not just the state.** Facts are the present. The recent events for the region's
   places are the story, and the story is where inference lives ("the door unlocked, then the
   camera saw someone: that is April going out").
4. **Contracts say who she is, never what to conclude.** Register, honesty, silence rules. An
   inference written into a prompt is a line April can predict, and predictable is not magic.
5. **Guardrails stay in the world.** Cooldowns, quiet hours, one voice per event, hard caps on
   turns. The model may choose silence; it may not choose to shout every fifteen seconds.
6. **Two models, two jobs.** The live line runs on the fast model at low effort: time to first
   sentence is the metric. Memory consolidation runs on the best model April will pay for: latency
   is irrelevant and quality compounds day over day.
7. **Viewable.** Every consideration — spoken or quiet — is a decision in the Viewer with the
   facts and happenings it saw; every episodic memory is a fact in the Facts panel with its
   provenance; the glossary is a Wizard-editable table. "Considered, stayed quiet" is a state.
8. **Private things stay private.** Raw texts never leave the Bridge's Mac; the world sees the
   extracted fact. The nightly job sees world events and conversations, not the sources behind them.

## Step 2 — Facts as facts, and the story

### What the mind receives

`PersonUtterancePercept` and `SceneTurnOffer` keep `worldFacts` and gain:

```swift
/// The world's recent events for the places and people this mind can see, newest last.
public var recentHappenings: [Happening]

public struct Happening: Codable, Hashable, Sendable {
    public var occurredAt: Date
    public var type: WorldEventType        // door.unlocked, camera.person_seen, facts.given …
    public var subjectID: EntityID         // place:front-door, person:jesse
    public var summary: String?            // the event's own one-liner, if it has one
}

/// What a predicate means, for the glossary. Rendered only for predicates present.
public var factMeanings: [String: String]  // "door.lock": "whether the deadbolt is thrown …"
```

The world fills `recentHappenings` from the event log: the last `knowledge.happenings_minutes`
(default 15) for the subjects `PresentWorldKnowledge` already expands to (region, present
characters, the region's places, people named), capped at `knowledge.happenings_limit` (30).
Heartbeats, timers, and `environment.measurement_changed` are excluded; a measurement is state,
and it is already in the facts.

### How the mind renders it

`FactPhrasing.lines` is replaced by one generic renderer in the agent (kept in the agent so the
world never authors prompt text):

```
What the world knows right now (newest first; "assumed" means nobody has checked):
- front door · lock = unlocked · since 8:03 PM (5 min ago) · observed
- carport · seen person · 8:08 PM (just now) · observed
- April · presence = home · since 6:12 PM · assumed
- Jesse · expected = "this afternoon, to finish the deck" · until 6 PM · April said so
- Jesse · description = "April's contractor" · April said so
- outside · temperature_f = 67.1 · 2 min ago · observed
- the room · last scene · 8:09 PM: Beaky "…", Kenny "…"

What those mean:
- lock: whether the deadbolt is thrown, from the smart lock; says nothing about the door being open
- seen person: a camera's person detector fired there; it cannot tell who
- presence: where the house believes someone is, from their phone; "assumed" is a guess

What just happened (oldest first):
- 8:03:05 PM  front door unlocked
- 8:03:10 PM  person seen at the front door
- 8:03:24 PM  person seen in the driveway
- 8:08:02 PM  person seen at the carport
```

Subject names come from the entity ID as today (`place:front-door` → "the front door"; a
`person.description` fact adds nothing to the name, it is its own line). Values render as
themselves; numbers round to one decimal; measurements keep their unit from the predicate suffix.
The three special lines stay: the local time in words, the model line, and "the cameras are
quiet" (which is itself an inference the world can vouch for). Pronouns still travel via facts to
the persona. Everything else in `FactPhrasing` goes, with its tests replaced by tests of the
renderer and of the world's `factMeanings` selection.

### `fact_kinds` in Mongo

```json
{ "_id": "door.lock", "meaning": "whether the deadbolt is thrown, from the smart lock; says nothing about whether the door is open", "updated_at": …, "updated_by": "wizard:april" }
```

Seeded from a list in `WorldCore` (the predicates the reducers produce, with their meanings —
code that *produces* a predicate is the right place to say what it means), upserted at startup
without overwriting a Wizard's edit. `GET/PUT /v1/fact-kinds` for the Viewer. A predicate with no
document renders with the meaning "unknown to the world yet" and the Viewer's Facts panel shows
it as a new word to define. Migration v9 creates the collection and index.

### Viewer

Timeline "knows N" becomes "knows N, saw M happenings"; the Mundane view of a consideration shows
the three blocks exactly as the mind saw them. Facts panel: a Meanings tab (Wizard Mode) listing
`fact_kinds`, editable in place, with undefined predicates at the top.

### Versions

World `0.15.0` (happenings, fact kinds, migration v9), agent `2.65.0` (renderer, `FactPhrasing`
retired), Viewer.

## Step 3 — Model-gated house remarks

### Widen the house

`creature-house` mappings gain the rest of the cameras (kitchen, orchard, the animal detectors),
the room motion sensors, and the weather turns. All become world events and facts. None become
`open_on` rules.

### The world offers, the mind judges

A new scene trigger path beside `open_on`: `scenes.consider_on` rules — event types and places
that *offer* the lead a remark rather than opening a scene:

```json
"consider_on": [
  { "event": "camera.*",  "cooldown_seconds": 120 },
  { "event": "door.*",    "cooldown_seconds": 60 },
  { "event": "motion.detected", "places": ["place:back-porch"], "cooldown_seconds": 300 },
  { "event": "person.arrived" }, { "event": "person.left" }
],
"quiet_hours": { "from": "23:00", "to": "07:00", "except": ["camera.person_seen", "door.unlocked"] }
```

The world sends the lead a `HouseRemarkConsideration` (the facts, the happenings, the event) with
a short deadline. The mind answers *speak* (with the line, streamed) or *quiet* (with a one-line
reason, for the Viewer). *Speak* opens the short house scene with that line already as turn one
— the other birds may react as today. *Quiet* is recorded as `house.remark_declined` with the
reason. `open_on` stays for the events that must always be said (the fallback line applies).

### Contract

The house-remark contract gains one paragraph: "You may stay quiet. Say nothing about routine
things — a bird at the feeder, the same delivery van, motion in a room April is already in —
unless there is something in it for April or something odd. Answer with `[quiet: reason]` to stay
quiet." The reason is never spoken; it is for the Viewer.

### Viewer

Timeline: `house.remark_declined` rows with the reason; Scenes panel: house scenes marked
"the house asked, Beaky spoke". A per-day count of considered / spoken / quiet.

### Versions

World `0.16.0`, agent `2.66.0`, house `0.2.0` (more mappings).

## Step 4 — Nightly memory

### The job

A world timer (`memory.consolidate`, default 03:30 local, and on demand from the Viewer: "Turn
back time, then remember") hands the memory model the day's events, conversation items, scenes,
and casts for each character, and receives:

- **Episodic facts**, `memory.episode`, subject the character, value `{ "when", "who", "what",
  "salience" }`, valid for `memory.episode_days` (default 30), provenance the events they came
  from. "Jesse came at 3:40 on Tuesday and put the boards on the deck; April was pleased."
- **Persona notes**, `memory.reflection`, one short paragraph per day, kept 90 days: what she
  learned about April, the house, the other birds. Rendered into the persona under "What you have
  come to know".
- **Standing facts** the day established (`person.description` for someone new, a running joke),
  proposed as casts with `epistemic: inferred`, shown in the Viewer for April to keep or discard.

Salience decides what a mind is given: the top `memory.episodes_in_prompt` (10) by salience and
recency, always including anyone named in the words.

### Models

`llmMemoryModel` in the agent config (default: the speaking model). April may set it to GPT-6.
The job runs in the agent (the mind owns its memories, and the API key is there); the world stores
the facts. `agent.memory_model` and `agent.memory_tokens` on the span.

### Privacy

The job sees world events and conversation items — things already in the world. It never sees the
Bridge's sources. Reflections are facts about the character, not dossiers on people: the contract
says so, and the Viewer shows every reflection.

### Versions

World `0.17.0`, agent `2.67.0`.

## Step 5 — Cutover

World, house, and gateway pointed at `server.prod.chirpchirp.dev`; three agents in `mode: world`
with the production creature IDs; the MQTT agent stopped and its unit disabled. `world.json` on the
production host from the package, with April's values. `docs/creature-agent-manual.md` marks MQTT
mode legacy. Measure the same driveway walk against the MQTT timing (MQTT: ~2 s; world tonight:
2.0 s from camera to line).

## Order and what each unlocks

| Step | Unlocks | Ships |
|---|---|---|
| 2 | She works out it was April in the carport; "Jesse's here" from an expectation cast at lunch | World 0.15, agent 2.65, Viewer |
| 3 | She notices the house all day and mostly keeps her counsel; the Viewer shows her judgement | World 0.16, agent 2.66, house 0.2 |
| 4 | "The deer was back last night"; "Is Jesse coming back to finish the deck?" | World 0.17, agent 2.67 |
| 5 | The MQTT agent retires | config |

## Open questions for April

1. Quiet hours: 23:00–07:00 with doors and people excepted — right for the house?
2. Should the other birds ever join a house remark, or is a house remark Beaky alone unless April
   answers? (Today: they may add one reaction.)
3. Memory model: start with Sol for consolidation and compare a week of reflections against GPT-6,
   or go straight to GPT-6?
4. Which cameras stay out of her sight entirely, if any?
