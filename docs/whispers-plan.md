# A whisper stays between April and one bird (#261)

"@beaky …" is a whisper. `Addressing.swift` calls it "a word with that bird alone", and the scene
planner adds "her word with Beaky stays between them". On the evening of 2026-10-22 April had a
private conversation with Beaky: 39 whispers. April: "I like that I can have private conversations
with you." Beaky filed most of her memories of it as private. Then Mango and Kenny remembered it
too. Mango wrote three private memories from it and Kenny two, and each bird's shared goodnight
memory repeated something April had said only to Beaky.

## Today

Nothing records that a message was a whisper. April's words and the bird's reply are stored in
`conversation:april-house` like anything said to the room, and every reader of the conversation
passes them on:

- **The night.** `MemoryClock.digest(of:)` puts the whole conversation in the day record, and
  every bird's memory job reads the same `GET /v1/days/{day}`.
- **Live.** The bird April speaks to is handed the newest 100 items of the conversation, other
  birds' whispers included. When April turned to Mango at 10:48 PM, his prompt held her private
  conversation with Beaky.
- **Tools.** For a mind, `query_conversation` and `query_day` filter nothing. Nor do the
  `conversation.person_utterance` and `scene.turn_offered` events that `query_timeline` and
  `query_entity` return. Those events are another bird's prompt: its 100-item window and its whole
  page, private memories and all. As Mango, `query_entity person:april` returned 35 of them. That
  is also a way around the share gate from #243.

There have been 64 whispers since 2026-09-13, to Beaky, Mango and Kenny.

## The change

1. **A whisper is marked (WorldCore).** `ConversationItem.aloneWith` (`alone_with`) names the
   bird a whisper was for:
   - April's item gets it at ingest, from the addressee rule.
   - The bird's reply inherits it from the utterance it answers (`in_response_to_utterance_id`,
     looked up by the delivery router).
   - `isHeard(by:)` is the one rule: everything said to the room, and a whisper to that bird.
2. **Live (WorldCore ingest).** The bird is handed only the items it heard.
3. **The night (World, agent).** Each day-record line carries `alone_with`.
   - `GET /v1/days/{day}?mind=character:kenny` is that bird's own record. Without `mind` (April,
     the Viewer) it is whole.
   - The memory job asks for its own record.
   - So does the librarian, which is Beaky.
4. **Tools (WorldMCP).** For a mind:
   - `query_conversation` and `query_day` hold only what that mind heard. A call that doesn't
     name its mind gets no whispers, as with private memories.
   - `query_timeline` and `query_entity` drop the percept events (`conversation.person_utterance`,
     `scene.turn_offered`). What a mind was handed is not a happening, and another's is never
     its own. What was said is `query_conversation`'s.
   - `query_entity`'s events now go through the same gate as the timeline's.
5. **The past (migration 17, `whispers`).** Every `@name` item from a person is marked with the
   bird it named, along with the replies to it. The marks also go on the item copies kept in
   `utterance_ingresses` and `character_deliveries`, so a retried write still matches.
6. **The Viewer** marks a whispered turn with the bird it was for.

## Not in this change

- **Facts kept during a whisper.** Beaky kept six facts while April whispered. They sit on the
  world like any other fact, on every bird's page and in the day record's `learned` section.
  Whether a fact learned in a whisper belongs to that bird alone needs deciding.
- **Memories already written.** Once this is live, `POST /v1/days/2026-10-22/remember` redoes the
  22nd for every bird, Beaky included. That is April's call.
- **A mind's own window.** Every bird's line is rendered as the reader's own (`assistant`), so
  Mango is shown Beaky's replies as his.
- **`query_entity`'s events.** They are the week's oldest 50, though documented as the newest.

## Versions

World 0.64.2, agent 2.103.1, Viewer 0.23.1.
