# Creature Agent Manual

`creature-agent` is a character's mind. It is one Linux executable with two modes:

| Mode | What it does | Where it runs |
| --- | --- | --- |
| `mqtt` (default) | Listens to Home Assistant events on MQTT topics and makes the creature speak a reaction aloud through Creature Server's ad-hoc speech pipeline. | **Production.** This is what makes Beaky react to the driveway today. |
| `world` | Lives in Creature World: follows the conversation stream, thinks with the local model over what April actually said, and answers through the world's delivery router. | **Development only** (April's Mac or fuzzball) until it can speak aloud. |

The design and roadmap live in [Beaky's World](beakys-world.md) (§8 and the dated handoff in
§0). The implementation plan for world mode is [`beaky-mind-plan.md`](beaky-mind-plan.md).

## World mode and production

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
sudo vim /etc/creature/agent/mango.yaml            # mode: world, characterEntityId: character:mango, creatureId, persona
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
llmSystemPrompt: |
  You are Beaky, an animatronic parrot who lives in April's house and is her familiar. ...
areas: []
```

Run it by hand for development:

```bash
creature-agent run --config-path agent.yaml --log-level info --host <creature-server> --port 8000 --insecure
```

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
- **It is told what the world knows** (`2.59.0`). The `world_facts` on an utterance percept or
  a scene floor offer are phrased as plain sentences — "Mango is here in the room with you",
  "April is home (you assume; nobody has checked)", "5 minutes ago, in this room: Mango said
  …" — in a "What you know right now, from the world itself" block ahead of the conversation,
  and the prompt says to trust it over guesses. `FactPhrasing` maps predicates to sentences,
  so the model never sees `presence.region`; a predicate it has no words for is left out
  rather than dumped. With no facts the block is absent. The Viewer's Mundane view of the
  percept shows exactly which facts a bird was told.
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
