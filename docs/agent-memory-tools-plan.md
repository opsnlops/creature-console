# The birds read April's project notebook (agent-memory), read only

Issue: [#294](https://github.com/opsnlops/creature-console/issues/294). Agent `2.110.0`,
World Viewer `0.26.0`.

## Why

April, after talking projects with Mango: it would have been neat if he could have looked up
the research she was doing *as she was doing it*. That research lives in agent-memory, the
shared memory her coding agents (Claude Code, Codex) keep: each project's state, decisions,
techniques, gotchas. It is an MCP server on the LAN.

The minds already reach for the world through tools (`worldMcpUrl`, agent `2.74.1`): the model
asks, the mind runs the call on the LAN, the answer goes back, and every call is cast as
`mind.tool_called`. agent-memory is the second server on the same path.

## Rules

- **Read only.** A mind is offered `search`, `get` and `list_tags`, the tools agent-memory
  marks `readOnlyHint`. `remember`, `update`, `edit` and `forget` are never offered, and a call
  to any name no server offered is refused in the mind (`ModelTools.UnknownTool`) before a
  request leaves it. Writes go to Creature World, as they always have.
- **The notebook is April's work, not the world.** The contract says to tell what was read as
  what her notes say, never as something the bird saw or remembers.
- **Only when it helps.** Like the world's tools, only on a turn that answers a person (a
  question from April, in the room or on the Communicator); house remarks and world events
  never carry tools.
- **The server stays on the LAN.** The model provider never reaches it; the mind does. What is
  read does go to the model provider, as every look-up's answer does.

## Design

- `MCPClient` (was `WorldMCPClient`) gains a session mode. agent-memory is stateful
  Streamable HTTP: `initialize` returns `Mcp-Session-Id`, every later request must carry it
  (else `400 Session ID is required`), and answers come as `text/event-stream`. The client
  opens a session on first use (`MCPSession` shares one opening between concurrent calls),
  names it with `MCP-Protocol-Version` on every request, reads the JSON-RPC response out of
  the event stream, and reopens once when the server answers 404/400 (it restarted).
  `_meta.audience` is sent only to the world.
- `ModelTools` holds several `ToolServer`s: each has a label (`world`, `agent_memory`), a
  catalogue already filtered and renamed, a call, and its own paragraph of the contract.
  The catalogues are concatenated for the model; a call is routed to the server whose
  catalogue lists the name.
- agent-memory's tools are offered as `agent_memory_search`, `agent_memory_get`,
  `agent_memory_list_tags`, with descriptions prefixed "April's project notebook (read
  only).", so they cannot be mistaken for `search_world`.
- Config: `agentMemoryMcpUrl`, independent of `worldMcpUrl`. April keeps production config in
  the package, and the birds' own yamls are not packaged, so the package gains a shared
  settings file, `/etc/creature/agent/common.yaml`, that every `creature-agent@<bird>` reads
  first (`--base-config-path`) and lays its own yaml over, key by key; `~` turns a shared key
  off for one bird. It ships `agentMemoryMcpUrl: http://10.19.63.10:8787/mcp`.
- April asked for the birds' own configs in the package too: they were copies of the old MQTT
  agent config with world keys added (`openAi*` keys the agent never reads, MQTT `areas`, a
  stale prompt - Caroll's was Mango's). Now `debian/creature-agent-<bird>.yaml` holds only what
  is the bird's own, shared values moved to `common.yaml`, and `llmSystemPrompt` is optional for
  a world-mode mind with a persona file. Checked before packaging: each bird's effective config
  is field-for-field what it was, apart from `agentMemoryMcpUrl`.
- Viewer: the Timeline's "looked it up" line now shows what was asked for (the arguments), so
  April sees "looked it up: agent_memory_search {"query":"music creation"}".

## Not now

- No per-project scoping: a bird may read every project's notes. Easy to add (a fixed
  `project` argument) if the notebook ever holds something the birds should not read.
- No writes, ever, from a mind. Their memory is the world's.
