# Creature Agent Manual

`creature-agent` is a character's mind. It is one Linux executable with two modes:

| Mode | What it does | Where it runs |
| --- | --- | --- |
| `mqtt` (default) | Listens to Home Assistant events on MQTT topics and makes the creature speak a reaction aloud through Creature Server's ad-hoc speech pipeline. | **Production.** This is what makes Beaky react to the driveway today. |
| `world` | Lives in Creature World: follows the conversation stream, thinks with the local model over what April actually said, and answers through the world's delivery router. | **Development only** (April's Mac or fuzzball) until it can speak aloud. |

The design and roadmap live in [Beaky's World](beakys-world.md) (§8 and the dated handoff in
§0). The implementation plan for world mode is [`beaky-mind-plan.md`](beaky-mind-plan.md).

## World mode and production

**World mode now covers what MQTT mode did** (World `0.10.0`): the house's camera detections
and door events open scenes on their own (`scenes.open_on` in `world.json`), so Beaky chimes
in when someone is at the driveway without anyone asking — with cooldowns per place, like the
MQTT agent's areas. The remaining difference is that MQTT mode spoke a fixed
`agentPrompt`-driven alert; world mode has the birds react in character, with the facts.

Production's agent (`mode: mqtt`) reacts to house events out loud. From `2.56.0`, world mode can
speak too: when Creature World puts Beaky in the room (April assumed or known to be home and
audible), the mind streams sentences to Creature Server exactly as MQTT mode does. What world
mode still lacks is the *house-event* side — reactions to MQTT topics — so replacing production's
agent means losing those until the world carries house events (VW-013). Run world mode on
production only once that trade is acceptable; the two modes are not interchangeable yet, even
though every release packages both.

## Installation

```bash
sudo apt install ./creature-agent_<version>_<architecture>.deb
```

The package installs `/usr/bin/creature-agent`, the units `creature-agent.service` and
`creature-agent@.service`, the sample configuration `/etc/creature/agent.yaml` (moved from
`/etc/creature-agent.yaml` in `2.57.0`; dpkg carries a locally edited file across), the
directory `/etc/creature/agent/` for per-character configurations, and the conffile
`/etc/default/creature-agent` (Creature Server host/port for the unit's `--host`/`--port`, and
the optional `OTEL_*` exporter settings); upgrades preserve local edits to all of them. On a host that already had a hand-made
`/etc/default/creature-agent` before `2.55.1`, dpkg asks about the conffile on the first upgrade —
keep the local version. The unit declares `StateDirectory=creature-agent`, so
`/var/lib/creature-agent` exists and is writable for the world-mode cursor. Build packages
locally with [`./build_debs.sh`](../README.md#debian-packages) instead of waiting for CI.
Upgrading restarts whatever is running — `creature-agent.service` and every active
`creature-agent@<instance>` — on the new version (#144, since `2.58.1`); a fresh install starts
`creature-agent.service` as before (debhelper's default for this package).

## Several minds on one host: `creature-agent@<instance>`

Every character is its own process (`docs/flock-plan.md`, principle 1). The template unit runs
one mind per instance name:

```bash
sudo vim /etc/creature/agent/mango.yaml            # mode: world, characterEntityId: character:mango, creatureId, personaPath: /etc/creature/agent/personas/mango.yaml
sudo vim /etc/default/creature-agent-mango         # optional: overrides of /etc/default/creature-agent
sudo systemctl enable --now creature-agent@beaky creature-agent@mango
```

Each instance reads `/etc/creature/agent/<instance>.yaml`, the shared `/etc/default/creature-agent`
and then `/etc/default/creature-agent-<instance>`, and keeps its own cursor in
`/var/lib/creature-agent/<instance>` (systemd's `STATE_DIRECTORY`, used when `stateDirectory` is
not set). `creature-agent.service` (`/etc/creature/agent.yaml`) remains for the single-agent
MQTT-mode deployment on production; do not run it alongside `creature-agent@beaky` for the same
character.

**Logging in.** In world mode a mind logs into Creature World as its character, in its region
(`regionEntityId`, default `region:home`), and heartbeats every 10 s. The world allows one mind
per character: a second process for the same character is told it is *logged in elsewhere* and
spectates — it logs, exports metrics, follows nothing and says nothing — retrying every 15 s
until the holder logs out or its session lapses (30 s without a heartbeat). Logins and logouts
are world events (`character.logged_in` / `character.logged_out`) and appear in World Viewer's
Characters panel. Stage and performance requests carry the session, so the world refuses turns
from a mind that does not hold the character.

**Scenes.** When the world opens a scene for April's words (more than one character is logged
into the region), the addressee's mind does not answer on its own — the percept carries a
`scene_id` and the mind records `in_scene`. Each mind is offered the floor in turn
(`scene.turn_offered`); it continues the scene with one or two sentences of its own, in its own
voice, or passes (`[silence]`), and answers the world at `POST /world/v1/scenes/{id}/turns` with
its session. The world performs the whole scene once it closes; nothing is streamed to Creature
Server for a scene turn.

## Configuration (`/etc/creature/agent.yaml`)

Shared keys:

| Key | Default | Meaning |
| --- | --- | --- |
| `mode` | `mqtt` | `mqtt` or `world` |
| `creatureId` | required | Creature Server creature **UUID** Beaky speaks through (both modes; Beaky is `4754fc0e-1706-11ef-931d-bbb95a696e2e`). The sample file's `<uuid>` placeholder makes Creature Server refuse every session with `creature_id must be a UUID` |
| `llmBackend` | `openai` | `openai` or `local`; world mode requires `local` |
| `llmModel` | `gpt-5.2` | model name sent to the backend |
| `llmSystemPrompt` | required | the character's persona |
| `llmTemperature` | `1.0` | |
| `localLlmHost` / `localLlmPort` | `10.69.66.4` / `1234` | llama-server (OpenAI-compatible) |
| `localLlmMaxTokens` | `100` | enough for a short reply; set `400` or so in world mode so a story fits. If the model is cut off by this cap, the unfinished last sentence is dropped rather than spoken (#157) |

MQTT mode keys (`mqttHost`, `mqttPort`, `mqttReconnectBackoff`, `fallbackSpeech`,
`maxConcurrentTasks`, `minSentenceChars`, `areas`) are documented in the sample file. `areas` is
required in MQTT mode and optional in world mode.

World mode keys:

| Key | Default | Meaning |
| --- | --- | --- |
| `worldUrl` | `http://127.0.0.1:8001/world/v1` | Creature World API |
| `characterEntityId` | `character:beaky` | which character this process is |
| `personEntityId` | `person:april` | whose utterances it answers (first version) |
| `stateDirectory` | `/var/lib/creature-agent` | where the world cursor is kept |
| `maximumReplyAge` | `3600` | seconds; older messages become recorded `stale` silences |
| `maximumContextTurns` | `20` | newest prior turns sent to the model |
| `llmTimeoutSeconds` | `60` | model call deadline |
| `regionEntityId` | `region:home` | the region this mind logs into; a character is in one region at a time |
| `stage` | `physical` | `physical` asks the world for the stage and speaks in the room when told to; `communicator_only` never asks (2.55 behaviour) |
| `worldMcpUrl` | unset | `2.74.1`, OpenAI backend only: WorldMCP as the model's tools, reached by **this mind** (`http://127.0.0.1:8001/world/mcp` beside the world; the LAN address elsewhere). The model asks; the mind runs the call. See *She looks things up* below |
| `llmBackend` | `local` | `local` (Mistral on the LAN) or `openai` (`2.61.0`): a mind may run on OpenAI's Responses API, streamed sentence by sentence like the local model, so one bird can be compared against Mistral live (`llm.model` is on every span). The key comes from `OPENAI_API_KEY` in `/etc/default/creature-agent-<instance>` (never in git) or `llmApiKey` |
| `llmReasoningEffort` | none | `low`, `medium`, or `high` for OpenAI reasoning models; when set, no `temperature` is sent |
| `llmServiceTier` | none | OpenAI `service_tier`: `fast` buys lower latency for a per-token premium (about 2× on the models that support it); a bird in a room may be worth it (`2.62.0`) |
| `personaPath` | none | a persona file (`docs/personas/<bird>.yaml`, installed under `/etc/creature/agent/personas/`); with it the mind *is* that persona and `llmSystemPrompt` is ignored in world mode (`2.60.0`) |
| `timeZone` | the host's zone | an IANA identifier such as `America/Los_Angeles`; the mind is told the local time in words every turn ("It is 11:45 PM on Friday, September 11."). Set it — a server's clock is usually UTC and a model cannot convert zones (`2.59.0`) |

A minimal world-mode file:

```yaml
mode: world
creatureId: 4754fc0e-1706-11ef-931d-bbb95a696e2e
llmBackend: local
localLlmHost: 10.69.66.4
localLlmPort: 1234
llmModel: mistral-nemo
llmTemperature: 0.9
localLlmMaxTokens: 400
worldUrl: http://10.69.66.1:8001/world/v1
characterEntityId: character:beaky
personEntityId: person:april
stateDirectory: /var/lib/creature-agent
timeZone: America/Los_Angeles
personaPath: /etc/creature/agent/personas/beaky.yaml
llmSystemPrompt: |
  You are Beaky, an animatronic parrot who lives in April's house and is her familiar. ...
areas: []
```

Run it by hand for development:

```bash
creature-agent run --config-path agent.yaml --log-level info --host <creature-server> --port 8000 --insecure
```

### Running one bird on a frontier model

The spike April asked for on 2026-09-12 ("compare a frontier model vs Mistral… GPT 6 on a low
effort"): switch a single mind's backend and leave the others on Mistral.

```yaml
# /etc/creature/agent/beaky.yaml
llmBackend: openai
llmModel: gpt-6-astra
llmReasoningEffort: low
llmServiceTier: fast        # optional; premium per token, lower latency
```

```
# /etc/default/creature-agent-beaky
OPENAI_API_KEY=sk-...
```

Then `sudo systemctl restart creature-agent@beaky`. The log's `Model chosen` line confirms the
backend. (`2.62.1`: the stream is read with AsyncHTTPClient — on Linux, a `URLSession` built
per request aborted the process with `_MultiHandle deallocated with non-zero retain count`
as each HTTPS stream ended.) Honeycomb's `llm.model` on `agent.consider` / `agent.scene.consider` lets you compare
turn latency, `chose_silence`, and what the sanitizer had to strip, bird by bird. Everything
else — persona, facts, the clock, streaming to the room — is identical.

## How world mode behaves

- **It starts from the present.** With no cursor it begins at the world's current sequence; Beaky
  does not wake up and answer three days of backlog. With a cursor it resumes with `Last-Event-ID`
  and answers anything it missed, except messages older than `maximumReplyAge`, which become
  recorded `stale` silences.
- **It reads the canonical conversation.** The prompt is the persona, a fixed conversation
  contract (`prompt_version` `world-conversation-v2`, recorded on every span), and the prior
  conversation items the world attached to the percept — both authors, in order — so Beaky sees
  what she herself said last. Consecutive messages from one author are merged into one turn
  because Mistral's chat template rejects non-alternating roles.
- **It is laid out for the cache** (`2.75.0`). April: "We are not using token caching well
  at all." A frontier provider charges a fraction for the unchanged *prefix* of a prompt, so
  on the OpenAI backend the prompt is layered: one system message with the persona, the
  contract, and the glossary (stable from call to call), then the conversation so far, then
  a second system message with the facts of the moment and the time, then the newest turn.
  Everything before that second message is the same text as the last call — a bird's
  scene turns and answers share it — and `prompt_cache_key` (the character id) keeps one
  bird's requests on one cache. The local backend keeps the single system message its chat
  template needs.
- **It is who its persona says** (`2.60.0`). With `personaPath`, the system prompt is the
  persona rendered in sections — who you are, how you talk, what you care about and steer away
  from, *the ones here and how you feel about them* (only the characters the world's presence
  facts or the scene's participants say are present, plus the speaker), running jokes, and
  `never` rules last — followed by the contract and "What you know". A persona's `pronouns`
  go to the world at login and come back to every other mind as an `identity.pronouns` fact,
  so the ones here are named with theirs: "Mango (he/him) is here in the room with you",
  "- Kenny (he/him): Protective…". A bird's pronouns live in that bird's file only. Rendering is deterministic,
  so a persona edit reviews as a diff of what the model reads; `agent.persona_version`
  (`name/version`) is on every `agent.consider` and `agent.scene.consider` span. Restart the
  mind after editing a persona. See [`docs/personas/README.md`](personas/README.md).
- **Scene turns stream** (`2.63.0`, #175). With a streaming model (local or OpenAI), a scene
  turn is composed and sent sentence by sentence: the first sentence decides silence and
  loses any speaker label or hail, every sentence is speech-clean and stage-direction-free,
  each goes to the world (`piece: n`) as it lands and is spoken there, and the turn ends
  with "that was the whole line". `llm.first_sentence_ms` on `llm.generate` measures what
  April actually hears. If the world cannot take a piece, the turn is retried from the
  cursor and the pieces already taken are recognised by index.
- **Nobody hails April every line** (`2.60.1`). In a scene, a turn that opens with the name of
  the person who started it as a vocative ("April, pizza or Linux?") loses the vocative; a
  name later in the line, or another bird's name, is kept, and solo replies are untouched.
  The scene contract also says to speak to whoever you are answering.
- **Stage directions are never spoken** (`2.60.0`). `*giggles*`, `(chuckles)`, `[flaps wings]`
  are removed from every reply before it is stored or spoken; a reply that was nothing but a
  direction is a pass. The persona's `never` rules make narration rare; this makes it impossible.
- **It knows what it runs on** (`2.62.0`). "Your mind runs on the openai/gpt-6-astra model.
  Say so if April asks; otherwise it is not worth mentioning." is the second line of "What
  you know" — April decided a familiar should be able to answer "what model are you using?"
  while the persona still keeps her from volunteering it.
- **It is told what the world knows** (`2.59.0`; reshaped in `2.66.0`). The block begins
  with the local time in words (`timeZone`) — Beaky answered "high noon" at 11:45 PM before
  this — and then every `world_fact` on the percept or floor offer in one shape: who or where,
  the predicate, its value, since when, and how it is known — `The front door · door.lock =
  unlocked · since 8:03 PM (5 minutes ago) · observed`, `April · presence.state = home · since
  6:12 PM · assumed (nobody has checked) (90% sure)`. Below that, "What those kinds of fact
  mean": the world's glossary for the predicates present (`fact_meanings`, from the world's
  `fact_kinds`), and "What just happened around you": the `recent_happenings`, oldest first,
  with the clock and the age. There are no phrasing templates: a frontier model reads facts as
  facts and says them in the bird's own words, and a new kind of fact needs a meaning in the
  world, never code here. Three lines are still the agent's: the time, the model line, and the
  quiet cameras. The Viewer's Mundane view of the percept shows exactly what a bird was told.
- **Nothing new, nothing said** (`2.69.0`). In a scene, a turn is taken only if it adds
  something new for April — a fact she does not have, a question she needs to answer, a joke
  that lands once; agreeing, restating, riffing on one's own subject again, or re-answering is
  not new. Otherwise the mind replies `[pass: why]` (a house question: `[quiet: why]`); the
  reason rides the pass to the world, shows in the Viewer, and is never spoken. The contract
  says to expect to pass most turns. April: "Me telling Beaky I bought groceries doesn't need to
  be a 12 turn conversation about Linux."
- **She learns what April tells her** (`2.70.0`, step 4a). When April says something worth
  keeping — who someone is, that someone is expected and when, that a sighting was her or the
  postman, a correction — the mind ends its reply with `[learned: who or where | predicate |
  value | expires]`, one per thing, three at most: `[learned: Jesse | visitor.expected |
  Tuesday afternoon, to finish the deck | tomorrow]`. The tags are stripped before anything is
  spoken; each becomes a `facts.given` cast to the world with April as the source (`reported`),
  her words as provenance, and `valid_for_seconds` from `expires` (today, tomorrow, week, never)
  in the house's zone. Names become entities — "Jesse" → `person:jesse`, "the front door" →
  `place:front-door`, "the house" → `houseId` (default `house:aprils-nest`). Only what April
  said, never the mind's own guess; the Viewer shows "Beaky learned: …" with a Forget button.
- **A bird is a bird** (`2.71.3`). "Kenny" in a learned tag or a memory episode is
  `character:kenny`, never `person:kenny`: one resolver (`EntityNames`) knows the birds — this
  one, whoever the world says is present or spoke that day — and guesses person or place only
  for names it does not know. The learned contract also asks for a kind the world already has
  before inventing one, and not to keep what another bird just kept in the same scene.
- **A departure is told plainly** (`2.72.4`). The house-remark contract forbids instructions
  and safety advice with one exception: when the house says leaving soon or time to leave, the
  bird tells April plainly and kindly, once, with the time, and lets it be.
- **No hands, and April's decisions are hers** (`2.72.3`). The scene contract says a bird cannot
  lock doors, set lights, or move anything - it can only say - and that a decision April has
  made is made: say your view once, then let it stand; never ask her to confirm it or press her
  to change it. The house-remark contract weighs facts by how they are known and how fresh
  ("something observed a minute ago outranks something expected later today").
- **Tags never reach the room, in scenes either** (`2.72.2`). Beaky said "[learned: April
  medical.labs …]" aloud: the scene path stripped think-tags but not learning tags. They are
  stripped before speech now, across sentence boundaries.
- **A known name is that entity** (`2.72.2`). A learned fact or memory about a name the world
  already holds - `thing:information-bridge`, `place:orchard`, an order - lands on that entity
  whatever kind the mind wrote; only a genuinely new name gets the mind's kind (or the
  person/place guess). Mango had filed the Bridge as `person:information-bridge`.
- **An earlier scene is a record, not an answer** (`2.72.1`). The scene contract's "already
  answered" means answered *in this scene*; a question April asks again gets a fresh answer
  from what the bird knows now, never a repeat of `scene.last`. (Mango had echoed a stale
  "expected tomorrow" and Beaky had passed on it.)
- **Remembering again replaces** (`2.72.0`). A day remembered a second time — by hand, or the
  clock after a by-hand run — is taken back first, every slot on every subject, then written
  afresh; the by-hand run and the clock run never stand side by side. A named thing in an
  episode — "thing: Hopper", April's car — is `thing:hopper`, not a person.
- **She remembers the day** (`2.71.0`, step 4b). With `llmMemoryModel` set (Beaky:
  `gpt-6-astra`; the chorus leaves it unset), the mind answers the world's nightly
  `memory.consolidate` by fetching the day's digest and asking the memory model for JSON —
  episodes about the people, places, and birds involved, with a human-grained `when` ("Sunday
  afternoon", never a clock time) and a salience 0–1, and one reflection in her own voice — and
  casts them as `memory.episode.<day>.<n>` / `memory.reflection.<day>` facts, kept for years. The job
  runs on its own so the stream keeps flowing; one night at a time. April: "She'll know 'Jesse was
  here on Monday' and not 'Jesse was here at 4:39:29 PM on Monday'." `OPENAI_MEMORY_API_KEY`
  in the instance's defaults file puts the night's spend on its own key.
- **Memory never keeps a phone number or an email address** (`2.75.5`). The first night of
  beliefs kept Polly's mobile number because the day's record had it; a memory is handed to
  the minds, so what is the world's alone must not get in by that door either. Episodes,
  reflections, and beliefs are scrubbed of phone numbers and emails before they are cast
  (an order number, which April wants kept, is not a phone number), and the prompts say so.
- **The presence sensor wins, and a chorus does not repeat the lead** (`2.75.5`, #193). The
  first live departure had all three birds say the same sentence, twice over, and an hour
  later they "could not tell who" came through the door six minutes after Home Assistant had
  said April was home. The house-remark contract now names the presence sensor as the
  authority: came home within twenty minutes, a person at the door or inside *is* April,
  said plainly ("April came home 6 minutes ago"); home for hours, it is her unless a visitor
  is expected; away, it is somebody else; a guess sounds like a guess only when it is one.
  The departure line belongs to the first bird; the chorus is told another bird has already
  told her and to react - a send-off, a wish, a joke - or stay silent.
- **She looks things up** (`2.74.1`; `worldMcpUrl`). April: "As the knowledge in the world
  grows we're quickly going to hit the limit of what we can pre-emptively send in the context
  to the agent." With `worldMcpUrl` set and the OpenAI backend, the mind asks WorldMCP for
  its tools at startup (`tools/list`, kept to `search_world`, the query tools and
  `explain_fact`) and offers
  them to the model as *function* tools on every question from April. When the model asks
  for one, the mind runs it against the world (`tools/call`, on the LAN - the model provider
  never reaches the world; April: "that's safer"), hands the answer back as a
  `function_call_output`, and the model goes on; at most three rounds, then it must speak.
  The contract tells her when: a question that needs more than what she was handed - who
  someone is, what happened on a day, what is scheduled, why a fact is what it is - never for
  a passing remark, never to re-check what is in the prompt, and with small limits (an
  answer past 16 000 characters is cut, and says so). A scene turn answering a person carries
  them too (`2.75.1` - April's question in the room is a scene); house remarks and world
  events never do; they must be quick. The first sentence of a look-up answer waits for the
  look-up. Every call is cast back as a `mind.tool_called` event on her (`tool`, `arguments`,
  `output_characters`, `error`), so the Viewer's Timeline shows "looked it up: query_entity".
  Every call the mind runs says it is a mind (`_meta.audience`), so a world-only fact - a
  phone number - never comes back through a tool (`2.75.4`, world `0.33.1`).
  A world that will not list its tools leaves the mind without them for the moment, never
  without a voice: the catalogue is asked for when a question needs it and a failure is
  retried after thirty seconds (`2.75.3` - deployed together, the mind came up before the
  world did and went a whole evening without tools).
  A local model has no tools.
- **She settles what she believes** (`2.73.0`, plan Phase 9; `docs/memory-consolidation-plan.md`).
  After the day's episodes, the same run reads the beliefs the flock holds and a month of
  episodes (paged from `GET /v1/facts?predicate_prefix=memory.`) and asks the memory model,
  in one JSON call, for what it believes now — kept, revised, dropped, added — and casts
  `memory.belief.<n>` on each subject: `{kind, what, salience, since, from}`, `kind` one of
  `habit`, `preference`, `relationship`, `self` (a bird's own patterns: "Mango's database
  joke has been made three times; it is worn out"). At most 4 per subject, 40 in all, and
  only on entities the record already names — a belief about a name nobody has an episode for
  is dropped, never a new person. The old set is taken back first, keyed by the run like the
  day's episodes. A `self` belief that a joke is worn out ends it: the scene contract says so.
- **Her words are written to be spoken.** Replies are sanitized for speech at the source (no
  emoji or symbols; digits are kept) so Communicator shows exactly what she would say aloud. A
  reply the model writes as a script line (`Beaky: "…"`) is stored as her words alone, so the
  format never enters her context and teaches the next turn to copy it (#154).
- **It never speaks twice.** The response identity is derived from the world's consideration ID,
  and the cursor advances only after the world accepted (`202`), reported a duplicate (`200`), or
  refused the turn. A crash between posting and recording replays the percept; if the model
  phrases its answer differently, the world keeps the first version and the mind moves on.
- **Silence is a decision.** `[silence]` from the model, an empty or unusable answer, a model
  timeout, a stale message, or a message from someone else all end as a logged silence with a
  reason and a `creature_agent.considerations.outcome` metric — never as an error.
- **It survives the world restarting.** Each stream connection uses a fresh HTTP client with a
  bounded connect, then reconnects from the cursor after a short delay.
- **It does not choose the stage — the world does, before the words exist.** With `stage:
  physical` (the default) the mind asks `POST …/stage` for each turn. If the answer is the room
  (`physical_speech`), it streams sentences to Creature Server's ad-hoc speech session
  (`--host/--port`, `creatureId`) as the model produces them — the session opens on the first
  speakable sentence, so `[silence]` never makes a sound — and then records the finished turn
  and its outcome with `POST …/performances`, so the Communicator shows the same words. If the
  answer is the Communicator, the full reply goes to `POST …/responses` as before. Creature World
  reports presence as `unknown` unless it is configured to assume otherwise (see the World
  manual's `presence.assumed`). `stage: communicator_only` never asks and restores `2.55`
  behaviour.
- **A room that will not speak is not a lost turn.** If Creature Server refuses the session, the
  turn is recorded as `failed` with `physical_speech_start_failed` (or `…_finish_failed`) and
  still lands in the shared history and the Communicator. A crash after speaking but before
  recording replays the consideration; the world answers `already_delivered` only if the record
  exists, so in that narrow window she may say it twice — visible in World Viewer as two attempts.

## Observability

The executable uses the shared OpenTelemetry bootstrap; set `OTEL_EXPORTER_OTLP_ENDPOINT` and
`OTEL_EXPORTER_OTLP_HEADERS` in `/etc/default/creature-agent` (or the shell) exactly as for
Creature World. In world mode each consideration is an `agent.consider` span under the trace the
utterance arrived with (phone → gateway → World → mind), with `llm.mistral.generate` and the
`creature.world.respond` POST as children. Span attributes carry IDs, the prompt version, the
model name, the reaction, and the suppression reason — never the text of what anyone said.
Metrics: `creature_agent.world.events.received`, `creature_agent.world.percepts.received`,
`creature_agent.world.reconnects`, `creature_agent.considerations`,
`creature_agent.considerations.outcome{outcome,reason}`,
`creature_agent.world.responses{disposition}`.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `Beaky's model did not answer` / `model_unavailable` immediately | llama-server refused the request; run with `--log-level debug` to see `Local LLM request failed: HTTP 400 …`. A non-alternating transcript is the classic cause and is handled; a wrong `llmModel` or an unloaded model is another. |
| `World stream interrupted; reconnecting from the cursor` repeating | World is down or `worldUrl` is wrong; the mind keeps trying. `Following the world` with `world.cursor=<n>` means it recovered. |
| Every restart answers old messages | `stateDirectory` is not writable, so the cursor never persists; check `StateDirectory` / permissions. |
| `Ignoring world cursor recorded against a different world` | The cursor file belongs to another `worldUrl`; the mind starts from the present. Delete the file to silence it. |
| Beaky answered the same message twice | Should not happen; capture the logs — the two turns will share a `conversation.response.id` if the world was bypassed. |
