# Entity kinds: the minds say, the Decisions API judges the rest (#239, step 1)

April: "Rather than use things like guessing with string splitting, go ask the minds." And: "We
could even use the decisions API since it's cheap. We don't need to send the full 10k prompt for
classification things."

## What goes wrong today

When a bird writes a name in a `[learned: …]` tag or a nightly memory's `about`, the agent
turns it into an entity id in `EntityNames.entity(named:)` (CreatureAgent/World/Learning.swift).
For a name it doesn't already know, it guesses the kind from word lists: `thingWords`,
`placeWords`, `looksLikeAPerson` ("one or two capitalized words") and `isMisfiledPerson`.
"Rocket Taco" is two capitalized words, so it became `person:rocket-taco`, and UUCWI became
`person:uucwi`. The fix for #236 then added another prefix test to find these after the fact.

## The change

1. **The mind says the kind.** The learned-tag contract and the nightly memory prompt ask for
   every subject as `kind: name`: "person: Jesse", "place: Rocket Taco", "place: the kitchen",
   "thing: Hopper", "spell: the TV spell". The two exceptions are a bird, by its name, and the
   house, as "the house". The bird has the whole conversation in front of it, so it's the one
   best placed to know.
2. **Whatever is still unclear goes to the Decisions API.** A bare name the world doesn't
   already hold is asked about as one `choice` question on `gpt-6-luna`, with the choices
   person, place, thing, spell or nobody (a group, or not something to file a fact on). The
   input is short: the name, the tag, the last six turns of the conversation or scene (April:
   "add in some of the conversation that was happening around the word"), and the bird's reply,
   or the memory's sentence. That's about 360 tokens, never the bird's 10k prompt. Tried live on
   2026-10-16: with the conversation, five of five ambiguous made-up names were right (UUCWI went
   from "thing", 0.18, to "place", 0.89); with the tag alone, three of five. A wrong call is still
   the librarian's to fix, but a good one leaves her less to clean up. It costs $0.10 per million
   input tokens and nothing for output.
3. **What stays code.** Parsing `kind: name`, bird names, "the house", and exact lookup of a
   slug the world already holds ("the world knows"). These are lookups, not judgements.
4. **Every word list goes.** `thingWords`, `placeWords`, `looksLikeAPerson`, `isMisfiledPerson`,
   the " and "/" all "/comma group test, and "the" meaning place.
5. **When there's no answer** (no API key, a local model, a failed or refused call), the fact
   isn't filed. The span records `agent.learned_unnamed` with the name, so it shows up instead
   of turning into a wrong guess.

## When it runs

The learned tags are cast after the bird's reply has been handed to the speaker, so the
classification runs while the animation plays and adds nothing to first-sentence latency. The
nightly memory runs at 3:30 AM. Each judgement gets a `agent.entity_kind` span with
`decisions.choice`, `decisions.confidence`, `decisions.duration_ms` and
`decisions.input_tokens`.

## Also removed: the Decisions shadow (#221)

The shadow asked, beside every scene turn, whether a bird would speak. It was ruled out for
that, so `DecisionsShadow`, `llmDecisionsShadow` and its plumbing go away.
`DecisionsClient` stays, gains `choice`, and `llmDecisionsModel` stays as the model setting.
A config that still says `llmDecisionsShadow` is ignored.

## Next (#239)

Step 2: the librarian judges every `person:` id for kind itself, in place of
`FilingDesk.kindCandidates()`'s prefix test.
