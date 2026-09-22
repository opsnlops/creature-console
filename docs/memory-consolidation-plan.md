# Memory consolidation — Phase 9, first slice

*2026-09-16. World `0.31.0`, agent `2.73.0`, Viewer `0.8.1`. Plan §4.10 and Phase 9 of
`beakys-world.md`.*

## What exists

- **Episodes** (`memory.episode.<day>.<n>` on the people, places, and house they are about):
  cast by the nightly job in the mind that owns a memory model (Beaky, on `gpt-6-astra`),
  from `GET /v1/days/{day}`. Human-grained, salience 0–1, kept for years, handed to a mind
  for `episode_days` (30) days, newest-and-most-salient first, `episodes_in_prompt` (10).
- **Reflections** (`memory.reflection.<day>` on the bird): a paragraph in her own voice;
  `reflections_in_prompt` (2), newest first.
- Repetition suppression within a scene, and against the last scene (`scene.last`).

What is missing, in the plan's words: *semantic* memory ("April gets excited about new robot
parts"), *relationship* memory (what Jesse is to the birds, accumulated), *autobiographical*
memory (the birds' own choices and patterns), and *consolidation* — the thing that turns
thirty days of episodes into a few durable beliefs before the episodes fade from the prompt.

## The slice: beliefs

One new memory family, **`memory.belief`**, kept for good and always handed to a mind:

```
person:april · memory.belief.1 = {kind: "habit", what: "April gets excited about new robot
  parts and wants to hear the moment a package is on the porch", salience: 0.9,
  since: "September 2026", from: ["2026-09-13", "2026-09-15"]}
person:jesse · memory.belief.1 = {kind: "relationship", what: "Jesse is April's contractor;
  he comes on weekend afternoons and texts when he is on his way", …}
character:mango · memory.belief.1 = {kind: "self", what: "Mango's database-schema joke has
  been made three times this week; it is worn out", …}
```

- **kind** is one of `habit`, `preference`, `relationship`, `self`. `self` beliefs live on
  the bird and are the autobiographical layer: what she has done, what landed, what is worn.
- **from** lists the days of the episodes the belief rests on — provenance in the value; the
  cast event is the consolidation run, so Why? shows the run and the run names the days.
- One value per subject and slot (`memory.belief.<n>`), at most `beliefs_per_subject` (4)
  per subject and `beliefs_in_prompt` (12) per prompt, most salient first. No horizon:
  a belief is current until the next consolidation revises or drops it.

### The nightly run, extended

`MemoryJob.remember(day:)` gains a second step after the day's episodes are cast:

1. Fetch every current `memory.belief.*` fact and every `memory.episode.*` fact of the last
   `episode_days` days (paged over `GET /v1/facts?predicate_prefix=`), plus the bird's last
   few reflections.
2. One JSON call on the memory model: *here is what you believed, here is what happened over
   the last month — write what you believe now.* Keep what still holds, revise what changed,
   drop what the record contradicts, add what several episodes now show. At most
   `beliefs_per_subject` per subject; a belief needs more than one day behind it unless
   April said it outright.
3. Retract the old belief set and cast the new one, keyed by the run (idempotent on retry,
   like the day's episodes). `memory.consolidated` gains `beliefs` in its payload.

Names resolve the way episode names do (`EntityNames`), seeded with every subject that has
an episode or a belief, so "the Information Bridge" lands on `thing:information-bridge`.

### Retrieval

`withMemoriesTrimmed` keeps beliefs apart from episodes: beliefs are never aged out, sorted
by salience, capped by `beliefs_in_prompt`. The glossary meaning tells the model what a
belief is (its own settled view, not an observation). The scene contract already forbids
reusing a joke from the last scene; a `self` belief that a joke is worn reaches further.

### Viewer

An entity's page shows beliefs in their own section, **Come to believe**, above
**Remembered**; the Characters panel shows a bird's `self` beliefs. Why? on a belief shows
the consolidation run.

## Not in this slice

Per-character beliefs (today all memory is the flock's, kept by the one mind with a memory
model); belief confidence decay; a "why do you think that" that walks from a belief to its
episodes by fact id (the days are in the value; the walk by id can come when the given-fact
reducer carries fact provenance); weekly rather than nightly consolidation (nightly is one
call and keeps the run idempotent by day).

## Done means

- A night's run on prod produces beliefs on April, the house, the birds, and any person with
  episodes; they show in the Viewer under **Come to believe**.
- A mind's perspective (`query_character_perspective`) carries the beliefs.
- `memory.consolidated` shows `beliefs: n`.

## Slice two: each bird's own memory (2026-09-21)

April, on reading the night's report: "What was Kenny's reflection?" There is none - one mind
(Beaky's) has a memory model, and it remembers the day *for the flock*: the episodes it writes
on Kenny say "I told her I loved her too", and the "I" is Beaky. This slice gives every bird
its own night: Kenny remembers the day as Kenny, in Kenny's voice, and what Kenny is handed
when he speaks is what Kenny remembers.

### The shape

A memory belongs to the bird that wrote it, and the predicate says so:

```
memory.episode.<bird>.<day>.<n>      memory.episode.kenny.2026-09-20.3
memory.reflection.<bird>.<day>       memory.reflection.kenny.2026-09-20
memory.belief.<bird>.<n>             memory.belief.kenny.1
```

The subject is still what the memory is about (`person:april`, `place:deck`, the bird itself),
so the Viewer's entity page still gathers everything known about April - now with "Beaky
remembered" and "Kenny remembered" apart. Two birds' beliefs about April sit side by side
instead of superseding each other, which is what the predicate slot is for.

- **World** (`0.37.0`): `WorldFacts.memoryOwner(of:)`; the facts a mind is handed include only
  *its own* memories (`FactRepository.Family.memories(of:)`, the mind being the first
  `character:` among the subjects asked for - every caller puts it first); the
  `characters/{id}/memories` resource is what that bird remembers, on any subject; a one-time
  migration renames Beaky's existing memories into the owned form (they were all hers).
  Meanings are still by family. Retention still never touches a memory.
- **Agent** (`2.80.0`): `MemoryJob` writes and reads under its own bird; the beliefs prompt is
  "what you have come to believe", never "the flock". Every bird with `llmMemoryModel` set
  remembers the night; the world's one `memory.consolidate` event fans out to each, in
  parallel, each through its own batch (~20¢ a bird a night on astra at batch rates).
- **Viewer**: Come to believe / Remembered grouped by the bird.

### Not in this slice

Birds sharing memories on purpose ("Beaky, tell Kenny what happened"); a bird remembering
what another bird said about it; per-bird persona/interest definitions (the personalities
phase proper). A bird with no memory model still speaks from the day's facts and story alone.

### Done means

- Three `memory.consolidated` events the night after deploy, one per bird, each with its own
  reflection; `query_character_perspective` for Kenny carries `memory.*.kenny.*` and nothing
  of Beaky's.
- The Viewer's entity page for April shows each bird's beliefs under its own name.
- Beaky's memories from before the change are still hers, still handed to her.

## Slice three: retrieval and not repeating oneself (2026-09-21)

Phase 9's exit: "characters coherently refer to prior shared experiences and their own
previous actions." Two things stand between here and there.

### Retrieval: a memory when it matters

Today a mind is handed its `episodes_in_prompt` most salient recent episodes, whatever the
moment is about. Ask Beaky about the deck three weeks after Jesse finished it and the
episode is gone from the prompt - not from the world, just from the page. Now the words of
the moment (April's question, the house's stage note) are searched against the mind's *own*
memories through the facts text index, and the `retrieved_in_prompt` (4) best matches ride
along beside the recent ones, whatever their age. No new contract: they are facts, and they
arrive as facts. `memory.retrieved_in_prompt` in `world.json`; 0 turns it off.

### Not repeating oneself: what you said lately

`scene.last` tells a bird what the *room* said in the last scene, for an hour. It says nothing
about what the bird itself said in the scene before that, and the next scene sometimes opens
before the last one has been reduced into it - which is how Kenny said the same line in two
back-to-back scenes. Now every percept carries the mind's own last `recent_lines` (8) spoken
lines from the world's own record (`scene.turn` events with words), across scenes, however
they happened; the contracts say "do not say any of these again in other words". The plan's
autobiographical memory, at its smallest: a bird knows what it just said.

- **World** (`0.38.0`): `FactRepository.search(_:limit:at:)` gains an `own` filter;
  `PresentWorldKnowledge` retrieves; `WorldKnowledgeProviding.recentLines(of:limit:)`;
  `SceneTurnOffer`, the utterance percept, and `CharacterPerspective` carry `recent_lines`
  (absent decodes as empty, so an older agent is unbothered).
- **Agent** (`2.82.0`): the moment renders "What you said lately" and the contracts point at it.
- **Viewer** (`0.11.0`): a character's perspective shows what it said lately.

### Done means

- "Beaky, how did the deck go?" weeks later answers from the episode, not "I don't know".
- Two scenes a minute apart never carry the same line from the same bird.
- `query_character_perspective` shows `recent_lines` and the retrieved episodes.
