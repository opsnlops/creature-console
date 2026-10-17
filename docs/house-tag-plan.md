# The bird asks the house (#240, part of #239)

April: "Let's start with the house tag as an experiment."

## Today

When April speaks, the World runs `SceneRequestRule` (WorldCore/HouseCommands.swift) before any
mind sees her words. It looks for the name of an offered scene, plus a trigger word ("set",
"turn", "lights", …), or for the scene's name with nothing but fillers around it. If it finds
one, it casts `house.scene_requested`, the house adapter sets the scene, and the bird is told
"April just asked for these lights and the house is setting them right now".

## The experiment

The bird reads the whole conversation anyway, so it decides.

1. **One switch, in the World.** `houseAsks: words | mind` in the World config, default
   `words`. With `mind`, the word rule doesn't run at ingress.
2. **The bird is told the scenes.** A new `GET /v1/house/asks` returns
   `{"asked_by": "mind" | "words", "scenes": [...]}`. The agent refreshes it every ten
   minutes, as it does the glossary. In `mind` mode the list and the contract ride in the
   prompt's stable item, so they're cached. In `words` mode the bird gets nothing new.
3. **The tag.** When April is asking for one of the scenes now (not mentioning it), the bird
   starts its reply with `[house: Movie Time]`. It's never spoken. The agent watches the
   reply as it streams, and the moment the tag has arrived, before the first sentence is
   spoken, it casts `house.scene_requested` from `mind:<bird>`. The payload carries the scene,
   `requested_by` April, the utterance id, and the response id as the source event id, so a
   retried reply asks once. Only a reply to something April said can ask: a camera or a house
   occasion never can.
4. **The World guards it.** A mind's `house.scene_requested` is refused unless `houseAsks` is
   `mind` and the scene is one the house offers; the name is normalised to the offered one.
   The house adapter already checks it against Home Assistant before setting it.
5. **What changes for April.** The lights change when the bird's reply starts, about a second
   later than with the word rule. No extra model call is made.

## Watching it

- The agent's span gets `house.asked` with the scene. The World logs "A scene was asked for"
  with the mind as its source.
- Misses show as a reply that says it's doing it with no tag (the Viewer's conversation), or a
  tag on a mention.
- Back to the word rule: `houseAsks: words`.

## Next (#239)

If this works, `SceneRequestRule` and its `triggers`/`fillers` lists are deleted, not kept as
a fallback.
