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
| `llmCache` | `{store: false, key: true}` | `2.77.2`: the provider's prompt cache knobs - `store` keeps responses on their side, `key` sends `prompt_cache_key`, `retention` sets `prompt_cache_retention` (e.g. `24h`). The raw usage object on every `LLM usage` line says whether a prefix was read (`cached_tokens`) or only written (`cache_write_tokens`); flip one knob at a time |
| `llmBackend` | `local` | `local` (Mistral on the LAN) or `openai` (`2.61.0`): a mind may run on OpenAI's Responses API, streamed sentence by sentence like the local model, so one bird can be compared against Mistral live (`llm.model` is on every span). The key comes from `OPENAI_API_KEY` in `/etc/default/creature-agent-<instance>` (never in git) or `llmApiKey` |
| `llmReasoningEffort` | none | `low`, `medium`, or `high` for OpenAI reasoning models; when set, no `temperature` is sent |
| `llmServiceTier` | none | OpenAI `service_tier`: `fast` buys lower latency for a per-token premium (about 2× on the models that support it); a bird in a room may be worth it (`2.62.0`) |
| `llmCaptureContent` | `output` | `2.88.0`: what was said, on the GenAI spans for Honeycomb - `off`, `output` (the birds' answers), or `all` (also April's words, the facts of the moment, and every look-up). The persona and contracts never ride along. See Observability. |
| `librarian` | `false` | `2.89.0`, #229: this mind is the flock's librarian - after remembering each night it files what all the minds kept. One bird (the lead), and only with `llmMemoryModel`. Watching for now: the proposal is recorded as `memory.filed` and nothing is changed. See "The librarian". |
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
as each HTTPS stream ended.) Honeycomb's `gen_ai.request.model` on `agent.consider` / `agent.scene.consider` lets you compare
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
  template needs. **Byte for byte** (`2.77.0`): the first cut hit the cache 2% of the time,
  because the "stable" item still carried who was present (in scene order), the situation
  (lead or chorus, where April is), and only the meanings of the kinds in that envelope. Now
  the stable item is the persona rendered for *everyone* it knows (sorted), the contract's
  constant core, and the world's **whole glossary** — held by the mind (`Glossary`, refreshed
  every ten minutes from `GET /v1/fact-kinds`), bigger but cached at a fraction — and the
  moment item begins "Here now: Beaky, Mango (he/him)." followed by the situation, the
  facts, the story, and the time. A kind the glossary does not know yet rides in the moment
  until the next refresh. `gen_ai.usage.cache_read.input_tokens` is how you know it is working. **The moment is a user item**
  (`2.77.5`): `probe-cache` showed a plain prefix caching 3/3 on every tier, key, effort, and
  format, while the client's own request with the world's own tools cached nothing across
  byte-identical rounds - the provider folds every developer message into one instructions
  block and hashes it whole, so a moment sent as a second developer item, changing every
  minute, emptied the cache on every call. It now goes out as a user item that opens with
  "(The world's note to you - not a message from April; her newest message follows it.)":
  3,798 of 3,847 tokens cached from round two. And every request body is encoded with sorted
  keys - ten tools with unsorted keys hit on round two and missed on round three - with a
  test holding twenty encodings of one request to one byte string.
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
  with "that was the whole line". `creature_agent.first_sentence_ms` on `invoke_agent {bird}` measures what
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
- **The chorus shares one prompt cache** (`2.97.0`, #235, docs/token-costs-plan.md). Every
  OpenAI request is in explicit cache mode (`llmCache.explicit`, default true): only marked
  parts are written to the cache. The stable item is one developer message in two cached
  parts, what every bird on the model is told alike first (contract, house scenes, glossary)
  and this bird's persona after it, and the last turn of the conversation so far is a cache
  point too. The moment and a night's memory are never written. `prompt_cache_key` is the
  model name, so Mango, Kenny and Caroll read one cached copy of the shared part; caches cross
  API keys within the organization, so each bird keeps its own key. The usage log line now
  uses `llm.usage.*` names, never the spans' `gen_ai.usage.*`. A local model's single system
  message is unchanged, persona first.
- **Old deliveries, and what the cache costs** (`2.96.0`, #234, #235). The librarian is told
  that a delivery a bird kept is news only for a few days, and to recommend retiring it once
  it arrived or was due more than three days ago; the mail's own orders the World settles by
  itself. Every chat span now carries `gen_ai.usage.cache_creation.input_tokens` (OpenAI's
  `cache_write_tokens`, billed at 1.25x) beside the cache reads, with the matching metric
  and usage log field.
- **What each scene is** (`2.95.0`, #241). The house-ask contract lists each scene on its own
  line with what it does, as `/v1/house/asks` describes it ("- Sleepy Time: Late at night,
  dims the outside lights…"); a scene with no description is listed by name, and a scene set
  aside in the Viewer is never listed. A World older than 0.55.0 sends no descriptions.
- **The bird asks the house** (`2.94.0`, #240, docs/house-tag-plan.md). When the World says
  the mind decides house asks (`GET /v1/house/asks`, refreshed every ten minutes like the
  glossary), the contract lists the house's scenes and asks for `[house: the exact name]` at
  the start of a reply when April asks for one, however she puts it. The tag is never spoken.
  The agent casts `house.scene_requested` from `mind:<bird>` as soon as the tag arrives, and
  only for a reply to April, never a camera or house scene. The span gets `house.asked`. With
  the World on `words`, or a World without the endpoint, the bird is told nothing and asks
  nothing.
- **The bird says the kind; a model judges the rest** (`2.93.0`, #239,
  docs/entity-kinds-plan.md). A learned tag and a memory episode name each subject with its
  kind: `person: Jesse`, `place: the front door`, `place: Rocket Taco`, `thing: Hopper`, `spell:
  the TV spell`. A bird goes by its name, and the house as "the house". A name the world already
  holds is that entity, whatever kind was written. A bare name nobody holds is judged by OpenAI's
  Decisions API (`llmDecisionsModel`, default `gpt-6-luna`): one `choice` (person, place, thing,
  spell, or nobody) from the name, the tag, the last six turns of the conversation or scene, and the reply (about 360 tokens), never the bird's prompt. It runs after
  the reply has gone to the speaker. No word list decides a kind any more: Rocket Taco was two
  capitalized words, so it was filed as a person. When there's no answer (a local model, or a
  failed or refused call) the subject isn't filed, and the span says
  `agent.learned_unnamed` (`memory.unnamed` for the night). Each judgement is an
  `agent.entity_kind` span with `decisions.choice`, `.confidence`, `.duration_ms` and
  `.input_tokens`.
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
- **A fact can be taken back** (`2.84.0`). A learned tag with the value `none` ends the fact
  instead of setting it — `[learned: Jesse | visitor.expected | none | today]` — cast as a
  `null` that closes what was held. The contract tells the birds to do it when April says
  something no longer holds: a visitor has left, a plan is off. On 2026-09-23 Jesse stayed
  "expected" all evening after April said he was gone; every camera sighting's stage note was
  "either her or Jesse", and all three birds kept asking. All three wrote the lesson into their
  memories that night ("being curious is not permission to keep asking the same question").
- **Spells, and nothing is a person by default** (`2.83.0`). A learned fact's subject used to
  fall through to `person:` whenever it had no place word in it, and the birds filed the
  Creature Server, the Mac Studio, the ferry, and "new spell" as people. The contract now names
  every kind — a person by name ("Jesse"), a place with "the" ("the kitchen"), a bird by name,
  "thing: Mac Studio", and **"spell: the TV spell"**: one of April's spells, what she builds to
  let the birds notice or do something (`spell:tv-spell`; world `0.42.0` knows `spell:` as a
  link kind). A bare name is a person only if it looks like one — one or two capitalized words,
  no possessive, no digits, none of the words that name things — and a group ("Kenny and
  Mango", "all three birds") is nobody, so the fact is dropped rather than misfiled.
- **Every silent turn says why** (`2.82.1`). A pass with no `[pass: why]` of the model's own —
  too late, the model gave nothing usable, the model did not answer in time — now carries that
  as its quiet reason to the world, so the Viewer never shows a silent turn with nothing beside
  it (Mango, 2026-09-19 7:10 PM).
- **A bird knows what it just said** (`2.82.0`, #205). The moment now ends with "What you
  yourself said lately, oldest first (do not say any of it again, in these words or others)" —
  the world's record of the bird's own last lines, across scenes — and both contracts point at
  it; the chorus rule that used to say "from the last scene" says "from what you said lately".
  With the world's retrieval (`0.38.0`), the memories the words call up arrive as facts among
  the rest, so nothing here changes for them.
- **Each bird remembers its own night** (`2.81.0`, #204). April: "What was Kenny's reflection?"
  — there was none; Beaky remembered for the flock, and the "I" in the episodes on Kenny was
  hers. Now every bird with `llmMemoryModel` set hears the world's `memory.consolidate` and
  writes its own memory under its own name — `memory.episode.kenny.<day>.<n>`,
  `memory.reflection.kenny.<day>`, `memory.belief.kenny.<n>` — reads back only its own when
  it consolidates, and is handed only its own when it speaks. Three birds, three batches a
  night, in parallel, each with its own `memory-pending.json` in its own state directory. To
  turn it on for the chorus: `llmMemoryModel: gpt-6-astra` in Mango's and Kenny's yaml (and
  `OPENAI_MEMORY_API_KEY` in their defaults files if the night has its own key).
- **The night goes through the Batch API** (`2.79.0`, #201). April: "let's look at using the
  batch API to reduce the cost of the nightly memory processor." gpt-6-astra is $10 per
  million in and $50 out; the Batch API is half of both, with an answer within the day - and
  nobody is waiting at 3:30 AM. With `llmMemoryBatch` on (the default), each stage of the
  night - the day's episodes, then the month's beliefs - is one line of a batch file
  (`OpenAIBatchClient`: upload, batch, poll, output file), the same request `respondJSON`
  would have posted, parsed the same way, its usage on the same `chat {model}` span
  with `creature_agent.batch = true` and `creature_agent.batch.id`. The night in progress is written to
  `<stateDirectory>/memory-pending.json` (day, run, stage, batch id) the moment a batch is
  submitted, and `MemoryJob.resume` picks it up on the next start - a deploy while the
  provider is still thinking loses nothing. A batch that fails, expires, or is still pending
  after `llmMemoryBatchWaitHours` (20) is cancelled and that stage is asked the ordinary way;
  the night always lands. `creature-agent probe-batch --model gpt-6-astra` proves the road
  end to end with a day key. Found on the way (#203): every night after the first was being
  skipped until a restart - the "still remembering" guard held a finished Task and asked
  `isCancelled`, which a finished task never is. It tracks completion now.
- **Pronouns beside every name** (`2.85.0`, #211). A fact line names its subject with the pronouns the world holds - `Natty (they/them) · person.relationship = …` - not only the "Here now" line, so a bird talking about someone who is not in the room still gets them right. A bird's pronouns still come from its persona config; a person's from April's address book, through the Bridge.
- **Decisions in shadow** (`2.87.0`, #221; removed in `2.93.0`). Asked, beside every scene turn, whether the bird would speak. It was ruled out for that, so the shadow and `llmDecisionsShadow` are gone (a config that still sets it is ignored); the Decisions client now judges the kind of a new name.
- **Someone already here is kept for the visit** (`2.87.3`, #228). The learning contract keeps a visitor who is already here for as long as such a visit takes - `[learned: thing: propane supplier | visitor.expected | here now, refilling the big tank | 2h]` - never `today`, and ends a visit with `none` on the visitor, not with a note on the place a camera saw. On 2026-10-14 the four birds kept the propane supplier until midnight, learned April's "long gone" only as a carport note, and asked about the tank visitor for every car that afternoon.
- **A quiet hour for the cameras** (`2.86.0`, #220). "Ignore the cameras for the next hour" is kept as `[learned: the house | house.cameras_quiet | the yard guy is working | 1h]`, and the world opens no camera scenes until it ends; "you can talk about the cameras again" ends it with `none`. Learned facts take spans now - `30m`, `2h`, at most `12h` - beside today / tomorrow / week / never. On 2026-10-06 the yard guy set off 33 camera scenes after April asked for quiet; the birds stopped mentioning cameras and talked about the weather instead.
- **Most likely April, after a look** (`2.85.3`, #214). The #200 rule said a person on camera *is* April when she is home, and the birds stopped looking - the tree sprayer and the Amazon driver were April. April: "They always assume it's me. (As we tell them to do.) They don't stop to think." Now: most likely her, but a camera sees a shape; a delivery due, a visitor expected, a car not hers, someone working outside, or a person somewhere she would not be may make it somebody else; her word outranks every sighting; and when nothing points elsewhere, speak as if it is her, without drawn-out hedging. Just after the presence sensor sees her arrive it is still "almost certainly" her.
- **April lives alone** (`2.78.0`, #200). The rule above covered "at the door or inside", and
  April comes home by the driveway and the carport: three birds made her arrival a "mystery
  visitor", and two hours later Beaky was still "guessing it's April, but the camera can't
  tell". One household rule now sits in *both* contracts, the house remark and the scene:
  when the house says she is home, a person on any camera, inside or out, is April unless
  a visitor is expected; call her April, never "someone" or "a visitor", and never say a
  camera cannot tell who it is. The world's stage note says the same in its own words
  (world `0.36.0`: "April is home and lives alone, so it is her"), so the mind is agreeing
  with the house, not arguing with a shape.
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
  emoji or pictographs; digits are kept, and so are the symbols a voice reads aloud - ASCII ones
  like `+` and `$`, currency signs, `° ± × ÷`, so "C++" stays "C++", #225) so Communicator
  shows exactly what she would say aloud. A
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

## Probing the provider's cache (`2.77.3`)

`creature-agent probe-cache --model gpt-5.6-sol` sends the same few-thousand-token prefix
three times, a fresh moment line each time, and prints the raw `usage` of each answer. With
`OPENAI_API_KEY` in the environment (`source /etc/default/creature-agent-beaky`). Try one
thing at a time: `--tier fast`, `--key character:beaky`, `--store`, `--retention 24h`, and
`--breakpoint '{"cache_control":{"type":"ephemeral"}}'` (a field added to the stable item -
a guess at how the provider wants a block marked; a wrong one is a 400 here). A working
cache shows `cached_tokens` in the thousands from round 2. On 2026-09-17 the live minds
showed `cache_write_tokens` of the whole input on every call and `cached_tokens` 0.

## The page

`2.90.0` (world `0.50.0`, #231): the world hands a mind thirty facts worth reading, with the
stage (who is in the room, pronouns) and the house's state - folded into one `environment.now`
and one `forecast.outlook` per place - beside them. The mind writes neither the stage nor
another bird's `presence.region` as a line: "Here now: Beaky, Mango (he/him)" says who is in the
room. Read a bird's page in the World Viewer's Page panel.

`2.91.0` (#232): a memory's meaning is looked up by its family (`memory.episode`), never written
into the moment once per memory; the nightly memory ends a belief or an episode at its last whole
sentence (700 characters at most) and asks for beliefs under 600.

## The librarian

`2.89.0`, #229, `docs/durable-learning-plan.md`. The birds keep what April tells them in the
moment, and the record scatters: on 2026-10-14 her flight training landed under September's
`flight.*` and the night's `person.flight_*`, and Mango's `person.flight_training` replaced
Beaky's five minutes after she kept it. Two things keep learning durable:

- **Seeing what is on file.** The world now hands a mind, beside the page's newest facts, the
  learned facts the words of the moment call up (`memory.facts_retrieved_in_prompt`, 6), so a
  bird told "landings are still hard" sees `flight.hardest_part` from a month before. The
  learning contract says to name a family by its topic (`flight.landings`, never
  `person.flight_landings`) and that a name holds one value: to add to a fact, keep the whole
  of it, old and new together.
- **Filing at night.** The mind with `librarian: true` (Beaky), after its own memory step,
  reads every current fact a mind kept (`GET /v1/facts?origin_prefix=mind:`), what a later
  keeping replaced in the last day (`/v1/facts/overwritten`), and the meanings of the families
  in use, and asks its memory model - batched when it can be - for a proposal: rewrites (facts
  on one topic folded into one, under one name), retires (no longer so), same (ids that are one
  thing; *sure* only when the record says so, never a person from a role alone), kinds (a
  meaning per family), and questions for April. The answer is held to the record: only ids it
  was shown, each fact once, dotted predicates, never a memory, at most 40 changes; the rest is
  counted as dropped.
- **Watching first.** The proposal is cast as one `memory.filed` event (`mode: watching`,
  source `mind:beaky`, keyed `librarian:<day>:<run>`) and nothing is changed. Read it in the
  World Viewer's Nightly panel. **Applying is April's, in the Viewer** (World `0.52.0`): she
  checks what she agrees with, and the World reviews each item against the record at that
  moment and applies what still stands, from `librarian:beaky`. The agent doesn't change for
  it; the proposal is the shared `LibrarianProposal` type the World reads. See the World
  manual's "Applying a night's filing".
- **Ids filed as the wrong kind** (`2.92.0`, #236). The record also lists the World's kind
  candidates (`GET /v1/librarian/kind-candidates`): every `person:` that no address-book card
  and no `person.*`, `contact.*` or `identity.*` fact names a person, each with a couple of lines
  of what is said of it. Beaky may propose `renames` (`{id, to, reason}`): the same name as a
  `place:`, `thing:` or `spell:`. A rename is held to the candidates and counts toward the 40.
  On 2026-10-16 the nightly memory had filed Rocket Taco and UUCWI, April's church, as people.
  A World older than 0.53.0 has no candidates, and the night files without them.
- In Honeycomb, the night is `agent.librarian.file` with `invoke_agent Beaky` beneath it
  (conversation `librarian:<day>:<run>`), and `librarian.rewrites` / `.retires` / `.same` /
  `.questions` / `.dropped` on the span.

## Observability

The executable uses the shared OpenTelemetry bootstrap; set `OTEL_EXPORTER_OTLP_ENDPOINT` and
`OTEL_EXPORTER_OTLP_HEADERS` in `/etc/default/creature-agent` (or the shell) exactly as for
Creature World. **Only there**: a bird's own `/etc/default/creature-agent-<bird>` is read after
it and overrides it, so `OTEL_*` lines left in one (a template's placeholder key) silently send
that bird's telemetry nowhere - Caroll sent none for his first week (2026-10-15). In world mode each consideration is an `agent.consider` span under the trace the
utterance arrived with (phone → gateway → World → mind), with the mind's model work and the
`creature.world.respond` POST as children.

**The GenAI semantic conventions** (`2.88.0`, #230, `docs/genai-semconv-plan.md`): the model
work is named the way OpenTelemetry's GenAI conventions name it, so Honeycomb's AI views
(AI Conversations, per-agent activity, token totals) see the birds. A turn reads:

```
agent.scene_turn
└─ invoke_agent Beaky              the mind's work for the turn (INTERNAL)
   ├─ chat gpt-5.6-sol             one per round (CLIENT)
   ├─ execute_tool query_entity    a look-up in the world (INTERNAL)
   └─ chat gpt-5.6-sol
```

- **`gen_ai.conversation.id`** is the scene for a scene turn, the consideration for a lone
  question, and the run for the nightly memory - so Honeycomb's conversation is one scene
  with every bird under it. Never `conversation:april-house`, which would make months one row.
- **On every round:** `gen_ai.operation.name = chat`, `gen_ai.provider.name = openai`,
  `gen_ai.request.model`, `openai.api.type = responses`, `gen_ai.request.stream`,
  `gen_ai.request.reasoning.level` (or `gen_ai.request.temperature`),
  `openai.request.service_tier`, `gen_ai.response.id`, `gen_ai.response.model`,
  `openai.response.service_tier`, `gen_ai.response.finish_reasons` (`stop`, `tool_calls`, the
  provider's reason when cut short, `error`), `gen_ai.response.time_to_first_chunk` (seconds,
  streamed), and usage: `gen_ai.usage.input_tokens` (cached included),
  `gen_ai.usage.cache_read.input_tokens`, `gen_ai.usage.output_tokens`,
  `gen_ai.usage.reasoning.output_tokens`. A failed round carries `error.type` (the HTTP
  status, or the error's kind).
- **A look-up's MCP call** is described on its `execute_tool` span (`mcp.method.name =
  tools/call`, `jsonrpc.request.id`, `server.address` / `server.port`, `network.transport`) -
  the MCP conventions ask for no second span when a GenAI tool span already covers it - and the
  trace rides in `params._meta.traceparent`, so the world's `tools/call {tool}` SERVER span is
  its child (world `0.48.0`). `tools/list` gets a CLIENT span of its own. A tool that answers
  `isError` is `error.type = tool_error`. Histogram: `mcp.client.operation.duration`.
- **On `invoke_agent`:** `gen_ai.agent.name`, the conversation, `gen_ai.output.type` (`text`,
  `json` for the night), the rounds' usage summed, and the last finish reason.
- **Ours, beside the spec's:** `creature_agent.call_kind` (`question`, `scene`, `house`,
  `memory`), `creature_agent.round`, `creature_agent.tools_offered`,
  `creature_agent.first_sentence_ms`, and `creature_agent.batch` / `creature_agent.batch.id`
  on a batch's answer.
- **What was said** - `llmCaptureContent`: `output` (the default, April's choice) puts the
  birds' answers on each round as `gen_ai.output.messages`; `all` adds what the model was
  handed (`gen_ai.input.messages` - April's words, the facts of the moment, earlier look-ups)
  and each look-up's `gen_ai.tool.call.arguments` / `.result`; `off` writes no words. The
  persona, contracts, and glossary never ride along: they are the large cached block, the
  same on every call.
- **Metrics:** `gen_ai.client.inference.usage.input_tokens`, `.cache_read.input_tokens`,
  `.output_tokens`, `.reasoning.output_tokens` (counters, `gen_ai.token.modality = text`),
  `gen_ai.client.inference.duration`, `gen_ai.client.inference.time_to_first_chunk`,
  `gen_ai.invoke_agent.duration`, `gen_ai.execute_tool.duration` (histograms in seconds, on
  the spec's buckets), each by provider, model, `creature_agent.call_kind`, and `error.type`.
  A batch's answer counts its tokens but not a duration.
- **The bill** in Honeycomb, **filtered to `gen_ai.operation.name = chat`** (the `invoke_agent`
  span carries its rounds' usage summed, so a query over every span counts it twice):
  `SUM(gen_ai.usage.input_tokens) - SUM(gen_ai.usage.cache_read.input_tokens)` grouped by
  `creature_agent.call_kind` is the uncached input; the ratio of cache reads to
  input is whether the prompt layout is working. Each round still logs one `LLM usage` line
  with the provider's raw `usage` object, for the prompt-cache experiments.
- The old `llm.*` attributes and the `creature_agent.llm.tokens` counter are gone (April:
  "Following the standard is better than backwards compatibility"). The spec is still
  Development; every name lives in `GenAITelemetry.swift`, so following a rename is one file.

Other span attributes carry IDs, the prompt version, the
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
