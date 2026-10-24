# A fact learned in a whisper is that bird's alone (#263)

#261 kept April's whispers between her and one bird. After it shipped, the 22nd was remembered
again, and the whispered conversation was gone from the chorus's memories. But two of its
topics came back. While April whispered, Beaky had kept facts on the world. A fact is the
world's like any other, so every bird was handed them, in its record of the day ("by mind:beaky:
…") and on its page. Mango and Kenny each remembered both, and shared them, reading them as
something "the house recorded". April: "let's go with the world deciding. It's more like real
life."

## The rule

A fact a bird keeps while answering a whisper is marked with that whisper's bird
(`Fact.aloneWith`, `alone_with`). Only that bird is handed it. The house's rules may still use
it, and April sees it in the Viewer. A later fact of the same kind said to the room replaces it
as usual.

## The change

1. **The World marks it at the door (`WhisperDesk`).** A `facts.given` from a mind is caused by
   the percept it answered (`caused_by`). When that percept is an utterance whispered to a bird
   (its ingress item carries `alone_with`, #261), the event's payload gets `alone_with`. A mark
   the mind sent itself is replaced, so the World decides. `GivenFactReducer` puts it on the
   fact.
2. **Every path to a mind is gated.**
   - **The page.** `FactRepository.heard(by:)` is the repository as one bird may know it, with
     every query through `currentQuery`. The page is built from it for the bird it is for: the
     thirty, the stage, links, mentions, the calendar, called-up facts and pronouns.
   - **The story.** A whispered `facts.given` is not another bird's happening.
   - **The day record.** Its `learned` lines carry `alone_with`, and `heard(by:)` filters them
     with the conversation.
   - **The tools.** For a mind, `visible()` drops another bird's whispered fact and its event.
3. **The librarian reads only what the room heard.** It is Beaky, and its questions are asked
   in the room, and what it files is the world's. `?room=true` on `GET /v1/facts`,
   `/v1/facts/overwritten` and `/v1/days/{day}`, and kind candidates are drawn from room facts.
   So a whispered fact is never filed. A merge that moves one carries its mark
   (`FilingApplication.Move.aloneWith`).
4. **The past (migration 18, `whispered_facts`).** For the whispered utterances: their percept
   events, the `facts.given` events those caused, and the facts derived from them, or moved
   from them by a filing, are marked.
5. **The Viewer** shows a whispered fact with the bird it was whispered to.

## Then

The 22nd is remembered once more, and Mango's and Kenny's two memories of it go.

## Not in this change

The house acts on what it knows: a whispered `visitor.expected` still lets it open a visitor's
scene when one arrives.

## Versions

World 0.64.3, agent 2.104.1 (the librarian), Viewer 0.23.2.
