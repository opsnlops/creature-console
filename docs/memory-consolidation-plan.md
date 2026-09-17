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
