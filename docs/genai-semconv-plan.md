# Creature Agent on the GenAI semantic conventions

*2026-10-15. Agent `2.87.3`. Plan only. Issue #230.*

## Why

Honeycomb's LLM features (the AI Conversations view, per-agent activity, token totals)
key on the OpenTelemetry GenAI attributes:

- `gen_ai.conversation.id`
- `gen_ai.agent.name`
- `gen_ai.operation.name`
- `gen_ai.usage.*`

Today the agent writes its own `llm.*` names. Honeycomb lists **zero AI conversations** in
production over the last week. Switching to the conventions should make each scene show up
as a conversation: every bird's turns, every model round, and every look-up in the world, on
one timeline, with what each one cost.

## The spec, as it stands

Source: [`open-telemetry/semantic-conventions-genai`][repo] at `f3c6d0c` (2026-10-14).

- **Stability.** Every GenAI convention is **Development**.
- **Releases.** The repo hasn't cut a release yet: its schema is `gen-ai-dev/1.42.0-dev`.
  Honeycomb's registry knows core semconv `1.41.0`, which already includes the names we
  need (`gen_ai.usage.cache_read.input_tokens`, `gen_ai.usage.reasoning.output_tokens`,
  `gen_ai.response.time_to_first_chunk`, `gen_ai.agent.name`, `openai.api.type`).
- **Opt-in.** The repo defines none, so we simply emit the latest.

[repo]: https://github.com/open-telemetry/semantic-conventions-genai

Expect renames while it settles. Several breaking changes are waiting in `changelog.d`, for
example: `gen_ai.client.token.usage` is gone, `cache_creation` became `cache_write`, and the
inference duration metric got its own name. The attribute names live in one Swift file
(below), so following a rename is a one-file change.

## Spans: today and after

A bird's turn today, and what each span becomes:

| Today | After | Kind |
|---|---|---|
| `agent.turn` / `agent.scene_turn` | unchanged: the world's turn, thinking and delivering | internal |
| `llm.mistral.generate`, `llm.generate` (the mind's model work for the turn) | `invoke_agent Beaky` | INTERNAL |
| `llm.openai.responses` (one per round) | `chat gpt-5.6-sol` (one per round) | CLIENT |
| a look-up in the world (no span today) | `execute_tool query_entity` | INTERNAL |
| `agent.memory.remember` | unchanged, with an `invoke_agent Beaky` inside | internal |

So a turn reads:

```
agent.scene_turn
└─ invoke_agent Beaky
   ├─ chat gpt-5.6-sol            round 0: asks to look something up
   ├─ execute_tool query_entity
   └─ chat gpt-5.6-sol            round 1: answers
```

The `llm.mistral.generate` names are left over from before OpenAI. They go away.

### `invoke_agent {bird}` (the mind's model work)

- `gen_ai.operation.name` = `invoke_agent`
- `gen_ai.agent.name` = `Beaky`
- `gen_ai.agent.description` = the bird's one-line persona summary, if there is one
- `gen_ai.conversation.id`: see below
- `gen_ai.output.type` = `text`, or `json` for the nightly memory
- `gen_ai.usage.input_tokens` / `output_tokens`, summed over the rounds
- `gen_ai.response.finish_reasons`
- Our own: `creature_agent.call_kind` (`question`, `scene`, `house`, `memory`) and
  `creature_agent.character_id`

### `chat {model}` (one model round)

- **Required:** `gen_ai.operation.name` = `chat`, `gen_ai.provider.name` = `openai`,
  `gen_ai.request.model`. Set them at span start, because they matter for sampling.
- **Request:**
  - `openai.api.type` = `responses`
  - `gen_ai.request.stream` (only when streaming)
  - `gen_ai.request.max_tokens`
  - `gen_ai.request.reasoning.level` (our `reasoning_effort`)
  - `openai.request.service_tier` (only when not `auto`)
  - `gen_ai.output.type` = `json` on JSON calls
  - `server.address` = `api.openai.com`
- **Response:**
  - `gen_ai.response.id`, `gen_ai.response.model`
  - `gen_ai.response.finish_reasons`: `["error"]` if a stream broke
  - `openai.response.service_tier`
- **Usage:**
  - `gen_ai.usage.input_tokens`, which includes cached tokens, as ours already does
  - `gen_ai.usage.cache_read.input_tokens` (was `llm.usage.cached_tokens`)
  - `gen_ai.usage.output_tokens`
  - `gen_ai.usage.reasoning.output_tokens`, from the Responses API's
    `output_tokens_details.reasoning_tokens`, which we don't read today
- **Streaming:** `gen_ai.response.time_to_first_chunk`, in seconds. This is the
  first-sentence latency we already chase, now under a standard name.
- **Errors:** `error.type`, either the HTTP status or our `OpenAIClientError` case.
- **Our own:** `creature_agent.round`, `creature_agent.tools_offered`.

### `execute_tool {tool}` (a look-up in the world)

- `gen_ai.operation.name` = `execute_tool`
- `gen_ai.tool.name`, `gen_ai.tool.call.id`, `gen_ai.tool.type` = `function` (we run them)
- `gen_ai.agent.name`, `gen_ai.conversation.id`
- `error.type` when the world couldn't answer

Today these calls leave only a log line. `OpenAIClient.run(_:with:)` is where the span goes.

### The nightly memory (Batch API)

The spec says nothing about batches. When a batch's results are read, each request in it gets
a `chat {model}` span carrying its usage, plus our own `creature_agent.batch.id`. Batch spans
have no meaningful duration (the work happened at OpenAI over hours), so the span says
`creature_agent.batch = true` and duration queries leave those spans out.

## `gen_ai.conversation.id`: which real id

The spec: only a real identifier, never a generated UUID, trace id or hash. The candidates:

- **A scene turn:** the **scene id**. A scene is the conversation: Beaky, Mango, Kenny and
  Caroll answering one thing April said, or one thing the house saw. In Honeycomb, one scene
  becomes one conversation, with every bird under it.
- **April's lone question (the Communicator path):** the consideration id. Each question
  becomes its own short conversation.
- **The nightly memory:** the run id (`memory.run`), one per bird per night.
- **Not** the world's `conversation:april-house`. It's one id forever, and Honeycomb would show
  months as a single conversation.

## Metrics

Following the spec, with token counters split by token type:

| Metric | Instrument | Notes |
|---|---|---|
| `gen_ai.client.inference.usage.input_tokens` | counter `{token}` | `gen_ai.token.modality` = `text` |
| `gen_ai.client.inference.usage.cache_read.input_tokens` | counter | |
| `gen_ai.client.inference.usage.output_tokens` | counter | |
| `gen_ai.client.inference.usage.reasoning.output_tokens` | counter | |
| `gen_ai.client.inference.duration` | histogram `s` | the spec's buckets |
| `gen_ai.client.inference.time_to_first_chunk` | histogram `s` | streaming only |
| `gen_ai.invoke_agent.duration` | histogram `s` | |
| `gen_ai.execute_tool.duration` | histogram `s` | |

Every metric also carries `gen_ai.provider.name`, `gen_ai.request.model`, `error.type`, and our
`creature_agent.call_kind`. If an inference fails, it still counts, with `0` tokens and its
`error.type`.

## The old names go

April's cache-rate queries and boards read `llm.usage.cached_tokens` and its siblings, and the
`creature_agent.llm.tokens` counter. April, 2026-10-15: "It's okay to wipe out our old
metrics. We can fix the dashboards. Following the standard is better than backwards
compatibility." So the old names are **not** written alongside the new: the release replaces
them, and the boards move to `gen_ai.*`. Any query on `llm.openai.responses` moves to
`gen_ai.operation.name = chat`.

## One place for the names

`GenAITelemetry.swift` in `CreatureAgent`:

- the attribute names as constants;
- `startInference(model:stream:…)`, `record(usage:on:)`, and `startTool(name:callID:)`;
- the metric instruments.

`OpenAIClient`, `CharacterMind`, `MemoryJob` and `OpenAIBatch` call it, and none of them spell
an attribute name. `LLMUsageRecord` folds into it. This keeps instrumentation in one place
instead of three ([[feedback-dry-facades]]), and one file to change when the spec renames
something.

## Message content: opt-in, off by default

The spec can carry what was said:

- `gen_ai.input.messages`, `gen_ai.output.messages`, `gen_ai.system_instructions`
- `gen_ai.tool.call.arguments` / `.result`

Each is a JSON string in Swift. Honeycomb's conversation view would show the birds' actual
words, but the prompts carry April's facts: contacts, calendar, where she is. Content
capture is a config switch, `llmCaptureContent`:

- `off`: no words at all
- `output`: only what the bird answered. **The default**: April, 2026-10-15, "Yes Honeycomb
  should get what the birds say."
- `all`: also the user item and tool calls/results

System instructions stay out even under `all`. They're the large cached block (persona,
contracts, glossary), the same on every call, and bigger than Honeycomb should be asked to
hold on every span.

## Testing

- Swift Testing, against an in-memory tracer: a fake streamed answer with one tool round
  produces `invoke_agent Beaky > chat > execute_tool > chat`, with the required attributes on
  each and the usage summed on the agent span.
- `error.type` on a 500 response and on a broken stream (`finish_reasons = ["error"]`).
- `conversation.id` is the scene id for a scene turn, and never `conversation:april-house`.
- Content capture: `off` writes no message attributes.
- Live, after deploy: `list_aiconversations` in production shows the night's scenes, one row
  per scene, with all four birds in the Agents column, and `get_aiconversation` on one shows
  the rounds and look-ups in order. Re-run that after deploy, not just the unit tests
  ([[feedback-test-real-shapes]]).

## Versions

- Agent: `2.88.0`. The CLI, MQTT and agent
  `top.swift` move together, with a tag and a Debian changelog entry.
- World: `0.48.0` (WorldMCP's server spans; no CLI bump of its own).
- `creature-agent-manual.md` (Telemetry) and §0 of `beakys-world.md`.

## WorldMCP, both ends (world `0.48.0`)

April, back from washing her hair: "Did you get WorldMCP, too?" The MCP conventions
(`docs/gen-ai/mcp.md` in the same repo) cover it:

- **The mind (client).** When a GenAI `execute_tool` span already covers the call, the MCP
  client SHOULD NOT make a second span; it adds `mcp.method.name`, `jsonrpc.request.id`,
  `server.*` and `network.*` to that span (`GenAI.toolSpan`, a task-local set inside
  `executeTool`). `tools/list` has no tool span, so it gets a CLIENT span of its own.
  `isError` is `error.type = tool_error`; a JSON-RPC refusal, its code.
  `mcp.client.operation.duration`.
- **The trace in `params._meta`.** `traceparent` / `tracestate`, unprefixed (SEP-414), beside
  the `audience` the mind already sends. HTTP headers would carry only the HTTP request.
- **The world (server).** Each message is a SERVER span, `tools/call query_entity`, whose parent
  is the context from `_meta` (or its own trace when a caller sends none),
  `mcp.protocol.version`, and, on a refusal, the code as `error.type` and
  `rpc.response.status_code`. `mcp.server.operation.duration`.
- **Names shared.** `Observability/MCPTelemetry.swift`, since the world and the agent both use
  them, and both pass the spec's buckets to the OTel bootstrap.
- **Tested.** The span shapes on both ends, the `_meta` merge, and refusals. The in-memory test
  tracer does not speak W3C, so the cross-process parent link is checked live: in Honeycomb, a
  bird's `execute_tool` has the world's `tools/call` beneath it.

## Not in this slice

- An `invoke_workflow scene` span. A scene is opened by the world, not the agent, so that span
  belongs in `creature-world`'s scene service. `gen_ai.conversation.id` already ties the
  birds of a scene together in Honeycomb.
- `gen_ai.evaluation.result` events. Later, the librarian (#229) or April's corrections could
  score a turn ("that was just the postman").
- Retrieval / embeddings spans, which come with vector search, if it comes.
