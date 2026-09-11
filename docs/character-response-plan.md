# Carrying Beaky's Turn — Implementation Plan

**Issue:** [#134](https://github.com/opsnlops/creature-console/issues/134)
**Roadmap:** Phase 3, Milestone B foundation (VW-030 #126 completion, VW-008 #99)
**Product:** Creature World `0.1.12` → `0.2.0`

## The magic this unlocks

April types to Beaky from her phone. For the first time, a turn *authored by Beaky* enters the
same conversation — durable, ordered, and pushed live to every open Communicator — with the world
having honestly decided where April could hear her. Nothing here writes Beaky's words; it gives
her a stage to stand on so that the agent (#105/#106) has somewhere to speak.

## What already exists

`WorldCore` holds the complete contracts and services (`CharacterUtteranceIntent`,
`CharacterDeliveryRouter`, `CharacterDeliveryRepository`, `PersonPresenceProviding`,
`CharacterDeliverySink`, `CharacterDeliveryDecision`, `CharacterDeliveryOutcome`) with 17
deterministic tests. `CreatureWorld` implements none of them. `World.reducers` is empty. No route
accepts a character turn.

## Design

```text
POST /world/v1/conversations/{id}/responses   (CharacterUtteranceIntent, trusted LAN)
  -> ConversationApplicationService.respond(intent)
  -> CharacterDeliveryRouter.route
       -> MongoCharacterDeliveryRepository.delivery(for: response_id)   (durable decision wins)
       -> UnknownPresenceProvider.presence(for: person)                 (state unknown, conf 0)
       -> decision: communicator / private / presence_uncertain
       -> repository.prepare: character_deliveries[_id = response_id] $setOnInsert
                              + conversation_items[_id = item_id]      (canonical turn is durable)
       -> CommunicatorDeliverySink.deliver -> accepted
       -> repository.record(outcome)
  -> provider publishes the stored ConversationItem via ConversationUpdateBroker
  -> SSE `item` on /world/v1/conversations/{id}/stream  ->  gateway  ->  Communicator bubbles
```

### Decisions

- **Presence is honestly unknown.** `UnknownPresenceProvider` returns `state: unknown`,
  `confidence: 0`, `valid_until == observed_at`. The router's existing rules then choose the
  private Communicator route with reason `presence_uncertain`. When VW-006/VW-013 land a real
  presence source, the provider is swapped; the router and everything downstream do not change.
- **The canonical item is persisted before any sink runs.** This is the router's existing
  contract; the Mongo repository honours it by writing `conversation_items` inside `prepare`.
- **The World publishes every newly durable Beaky item regardless of route.** A turn performed
  aloud (future) must still appear in Communicator history live. Publishing is therefore done by
  `MongoWorldPersistenceProvider.respond`, mirroring how `ingest` publishes April's item, not by
  the Communicator sink. Live push is at-least-once; clients upsert by item ID.
- **`CommunicatorDeliverySink` returns `accepted`.** Durable app delivery means the canonical
  item exists and live clients were offered it. `performed` is reserved for actual user
  interaction (future APNs/open/ack work), so the World never claims April saw something.
- **`PhysicalSpeechDeliverySink` is an honest placeholder.** It records `failed` with
  `error_code: physical_speech_not_connected` rather than throwing, so a turn routed to the room
  (unreachable until presence exists) is still durable and visible instead of retried forever.
  VW-016 replaces it with the Creature Server ad-hoc speech client.
- **Wire contract is snake_case with explicit `CodingKeys`** (`outcome`, `conversation_item`),
  learning from #133.
- **No gateway change.** The agent talks to World directly on the trusted LAN; Communicator never
  posts Beaky's turns.

### Files

| Area | Change |
| --- | --- |
| `Sources/CreatureWorld/MongoCharacterDeliveryRepository.swift` | new repository |
| `Sources/CreatureWorld/CharacterDelivery.swift` | presence provider, sinks, `CharacterResponseResult` |
| `Sources/CreatureWorld/MongoWorldPersistence.swift` | `characterDeliveries` collection + repository |
| `Sources/CreatureWorld/MongoWorldMigrator.swift` | migration v4 indexes |
| `Sources/CreatureWorld/MongoWorldPersistenceProvider.swift` | router wiring, `respond`, publish |
| `Sources/CreatureWorld/WorldAPI.swift` | `respond` on `ConversationApplicationService` |
| `Sources/CreatureWorld/WorldHTTPAPI.swift` | `POST …/responses` |
| `Sources/CreatureWorld/CreatureWorldBuildInfo.swift` | `0.2.0` |
| `Fixtures/CreatureWorld/character-response-result-v1.json` | wire fixture |
| `docs/creature-world-manual.md` | route + semantics |

### Tests

- `MongoWorldPersistenceTests`: delivery prepare is idempotent, records outcome, persists the
  canonical item in order with April's; migration v4 indexes exist.
- `MongoWorldPersistenceProviderTests`: `respond` publishes Beaky's item to a subscribed
  conversation stream; duplicate does not republish.
- `WorldHTTPAPITests`: 202/200 contract, identity mismatch 409, bad JSON 400, unavailable 503.
- `CharacterDeliveryTests`: unknown presence → private route; physical placeholder → failed.
- Linux: all four Debian products build in the Swift 6.3.3 container.

## Exit

Cast a Beaky turn with curl against fuzzball; it appears as a Beaky bubble on macOS and iOS
without reopening the app; re-POST of the same `response_id` returns `duplicate`; history paging
returns it after April's turns.
