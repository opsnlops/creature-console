# Learning that lasts

*2026-10-14, late. World `0.47.3`, agent `2.87.3`. Plan only: nothing here is built yet. Issue #229.*

## The night that showed it

On the night of 2026-10-14, April told the birds about her flight training: VFR, two to three
thousand feet, takeoffs fine now, landings still the hard part, the instructor wanting gusty
days. The birds kept it, but the record afterwards looks like this:

| On `person:april` | Value | Kept |
|---|---|---|
| `flight.aircraft` | flies a 1968 Piper Cherokee | Sep 28 |
| `flight.plane_owner` | her flight instructor owns the plane she uses for lessons | Sep 28 |
| `flight.hardest_part` | landings | Sep 28 |
| `flight.enjoys` | seeing everything from above | Sep 28 |
| `flight.hope` | hopes to own a plane someday | Sep 28 |
| `flight.school_gap` | about a month without a lesson, plane out for annual | Sep 28 |
| `person.news` | learning to fly a plane | Mango, tonight |
| `person.flight_preference` | enjoys seeing Whidbey, Hat Island, and Camano together… | Beaky, Mango |
| `person.flight_altitude` | usually two to three thousand feet during lessons | Beaky, Mango |
| `person.flight_rules` | flies VFR; needs to see the sky to fly | Beaky |
| `person.flight_training` | pretty much flies on her own outside of landings | Mango |
| `person.flight_takeoff` | can handle takeoffs after taking a while to learn | Mango |

Beyond that, `thing:1968-piper-cherokee · flight.training` says "manual controls", and the
school is filed under both `thing:wings-over-whidbey` and `thing:april-s-flight-school`. The
same thing happens elsewhere: the workshop is spread over six ids (`thing:new-workshop`,
`place:workshop`, `place:new-workshop`, `thing:old-pole-barn`,
`thing:april-s-creature-workshop`, `spell:creature-workshop`).

Four things go wrong:

1. **Scatter.** There are two naming schemes for one topic: September's `flight.*` and
   tonight's `person.flight_*`.
2. **Loss.** At 5:39 PM Beaky kept `person.flight_training` = "instructor wants her to fly in
   gusty wind conditions so she can learn". At 5:44 PM Mango kept `person.flight_training` =
   "pretty much flies on her own outside of landings". A predicate holds one value, so
   Beaky's fact is no longer current. Only the event log still has it.
3. **Near-duplicates.**
   - `flight.enjoys` and `person.flight_preference`.
   - `flight.hardest_part` = landings, beside "flies on her own outside of landings".
4. **Stale facts.**
   - `flight.school_gap` is a month old.
   - `person.news` "learning to fly" is not news.

## Why: the birds never saw September

The contract already says "Predicates: a kind from 'what those kinds of fact mean' when one
fits, else one already on that subject, else a short dotted word of your own". Facts already
reach a bird with their names (`April · flight.hope = …`). Even so, the birds made up new names
because the September facts were never on the page:

- `PresentWorldKnowledge.currentFacts` hands a mind the subjects' facts **newest first,
  capped at `WorldKnowledgeLimits.maximumFacts` (30)**, shared across April, the house, the
  birds, and the place.
- April has well over a hundred current facts. Six facts from September 28 are nowhere near
  the newest thirty.
- Retrieval by the words of the moment (memory slice three) searches only the mind's *own
  memories* (`facts.search(text, own: mind)`). It never searches what was learned.

So when April says "landings are still the hardest part", nothing puts `flight.hardest_part`
in front of the bird. "One already on that subject" can't be followed when the bird can't see
the subject's names. And the facts the bird *can* see, tonight's, are the newest, which is why
tonight's facts share their own `person.flight_*` scheme.

The loss is a separate gap: the contract never says that a predicate holds one value, or
that keeping it again replaces the old value. Mango had Beaky's `person.flight_training` on
the page (it was the newest fact) and wrote over it.

## The change: one change, two halves

One idea: **what a bird learns is filed with what is already known**. The first half prevents
the mess and the second cleans up what gets through. They ship together because they share
the vocabulary that keeps the filing durable: kind meanings in the glossary.

### Half one: see what is on file when learning (world + agent)

1. **Retrieve learned facts by the words of the moment.** Beside the memories, the words of
   the moment (April's line, the stage note) are searched against current **non-memory,
   non-world-only** facts, the same way slice three retrieves memories. The best
   `facts_retrieved_in_prompt` (6) ride on the page, whatever their age. "Landings are still
   hard" finds `flight.hardest_part = landings`. Configured as `memory.facts_retrieved_in_prompt`
   in `world.json`; 0 turns it off.
   - `FactRepository.search` gains a `family:` filter (`.notMemories`) and an `excluding:`
     filter (world-only kinds), mirroring `currentFacts(about:family:excluding:)`.
   - Search spans every subject, not only the page's: "my flight school" should find
     `thing:wings-over-whidbey`.
   - Not on the capped thirty: retrieved facts are their own section, like `retrieved`
     memories, so they never push the room's present facts off the page.
   - **The check that matters:** the text index stems English, so "fly" and "flies" meet but
     "flight" and "fly" may not. Run tonight's real lines through the real search before
     settling the number ([[feedback-test-real-shapes]]).
2. **Fix the contract (agent).** Two sentences in `Learning.contract`:
   - *A predicate holds one value; keeping it again replaces it. To add to a fact you can see,
     keep the whole of it, old and new together; for something else about the same topic, use
     another name in the same family.*
   - *Name the family by the topic, not the subject's kind: `flight.landings`, never
     `person.flight_landings`.*

   The contract lives in the cached developer block. It changes once, so the cache re-warms
   once.

### Half two: the librarian, once a night (agent + world)

After the birds remember the day, one **librarian** pass files what the minds learned. It
runs once for the world, not once per bird, because learned facts are shared.

- **Who runs it.** The first mind with `llmMemoryModel` that has `librarian: true` in its
  config (Beaky). It runs on the memory model, batched like the rest of the night, triggered
  by the same `memory.consolidate` event, after that mind's own memory step.
- **What it reads.** Every current fact a mind kept (see *Origin* below), grouped by subject,
  plus:
  - the glossary;
  - the last day's `facts.given` events from minds whose fact is no longer current and was
    not ended with `none` (*overwritten*, like the gusty-wind fact);
  - the names the world knows.
- **What it may never touch.**
  - Facts from the Bridge (contacts, calendar, mail, weather), the house, the body, or the
    world itself. Their sources would overwrite any tidying on the next sync.
  - Memories. Beliefs already consolidate those.
  - World-only kinds.
- **What it proposes**, as JSON, each item with a one-line reason:
  - `rewrite`: a new fact (subject, predicate, value) that replaces one or more current
    facts. This covers condensing, refiling to a better name or subject, and folding an
    overwritten value back in.
  - `retire`: end a fact that is stale or contradicted by a newer one.
  - `same`: these ids are one entity, keep this one. Marked `sure` only when the facts
    themselves settle it (`place:new-workshop` and `thing:new-workshop`). Otherwise it is a
    question.
  - `kind`: a meaning for a predicate family it settled on (`flight.training`: "where April
    is in learning to fly: what she does alone, what she still practices"), written to
    `fact_kinds` with `PUT /v1/fact-kinds/{predicate}`. **This is how the filing lasts.** The
    whole glossary rides in every bird's cached block (`Glossary`), so the next time anyone
    talks about flying, the contract's first choice, "a kind from what those kinds mean",
    finds `flight.*`.
- **How it is applied.**
  - Through the world's ordinary path: `facts.given` events from source `librarian:<bird>`.
  - Epistemic `reported`, because it is still April's word, refiled.
  - `derived_from` and `caused_by` point at the facts and events it came from.
  - A replaced or retired fact is ended with a null value, never deleted.
  - A `same` that is `sure`:
    - moves the facts onto the kept id;
    - leaves `entity.same_as = <kept id>` on the old one, which `EntityNames` follows, so a
      bird naming the old thing again lands on the kept one.
  - Idempotent by day (`source_event_id` = `librarian:<day>:<n>`), like episodes.
  - One `memory.filed` event per night summarises the run (counts, questions).
- **Questions for April.** A `same` that isn't sure is not applied. It goes into the night's
  `memory.filed` as a question, for example: "Is `person:amber` ('April's cleaning lady')
  the same as `person:tamara` (Quality Cleaning, Etc)?" April answers by telling a bird, which
  keeps a fact, and the next night's librarian sees the answer. There is no new answer UI in
  this slice.
- **Caps.** At most `librarian.changes_per_night` (40) applied changes, so a bad night can't
  rewrite the world.
- **A watching mode first.** `librarian.apply: false` writes the whole proposal into
  `memory.filed` and the Viewer without applying any of it. Deploy watching first, read a
  night or two of proposals, then turn on applying. One change at a time
  ([[feedback-one-change-at-a-time]]), even inside this change.

### Origin: knowing what a mind kept

A `Fact` doesn't carry its source today: `producer` is always the `given-facts` reducer,
and the source is on the event in `derived_from`. The librarian needs "every current fact a
mind kept" as a single query. That calls for:

- **`Fact.origin: SourceID?`**, set by `GivenFactReducer` from the event's source. It is
  absent on older facts and decodes as nil.
- A one-time migration that backfills it from each fact's deriving event.
- `FactRepository.currentFacts(origin prefix:)` and `GET /v1/facts?origin_prefix=mind:`.

This also gives the Viewer "kept by Mango" on any fact, which it lacks today.

## Viewer

Done means viewable ([[feedback-done-means-viewable]]):

- A fact shows **Kept by** (origin), and a fact the librarian made shows **Filed by the
  librarian** with Why? walking to the facts it replaced.
- The night's `memory.filed` shows on the timeline: what was rewritten, retired, merged, and
  the questions. In watching mode it shows the proposal in full.
- The entity page for a merged id shows "same as" with a link to the kept entity.

## Versions

- World `0.48.0`: origin and its migration, retrieval of learned facts, the `librarian:`
  source, `entity.same_as`, `memory.filed`.
- Agent `2.88.0`: contract sentences, the librarian job, and `EntityNames` following
  `same_as`.
- Viewer: a minor bump for Kept by, Filed by, and `memory.filed`.
- Debian changelog entry and tag for the agent release. §0 of `beakys-world.md` and both
  manuals updated in the same PR.

## Done means

- **Seeing it:** "Beaky, landings are still the hardest part" puts `flight.hardest_part` on
  Beaky's page (`query_character_perspective`), and what she keeps lands in `flight.*`.
- **Not losing it:** two birds adding to `flight.training` in one scene produce one fact
  holding both.
- **The first watching night proposes, for tonight's flight facts:**
  - a handful of `flight.*` facts;
  - `flight.*` kind meanings;
  - retiring `flight.school_gap` and `person.news`;
  - bringing back the gusty-wind fact;
  - merging the two flight-school ids.
- **The workshop:** the six workshop ids come out as merges or as questions.
- **Questions, not guesses:** Amber and Tamara come out as a question, never a merge.
- **The first applying night:** April's page in the Viewer reads like a filed record, and
  nothing from the Bridge or a memory changed.

## Not in this slice

- Birds asking April the librarian's questions themselves ("Is Amber the cleaning lady?").
  It would be lovely, and it's the next step once the questions prove good.
- Tidying facts the Bridge owns.
- Per-bird filing. Learned facts are the flock's.
- Splitting facts that cover too much.
- Vector search. Text search first, with every retrieval logged (April's words, what was
  found, what the bird then kept). If the misses are paraphrases ("the plane" vs "Cherokee"),
  vector search becomes its own change behind the same retrieval call: on MongoDB 9 with
  `mongot`, after a backup restore test and the upgrade from 8.3. Embed only what a mind
  kept and the birds' memories (`Fact.origin` is the filter), never sensor facts.
