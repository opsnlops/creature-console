# The page: thirty facts worth reading

*2026-10-15. Built: World `0.50.0`, agent `2.90.0`, Viewer `0.13.0`. Issue #231.*

April: "Remember that the goal is to make the 30 facts we deliver to the LLM to be high quality
facts." And: "I want to have high quality conversations with the birds. We need the facts to
be as full of context as we can."

## What the page held

Beaky's page for "landings are still the hardest part of flying" (`query_character_perspective`,
2026-10-16 03:45Z), the thirty `WorldKnowledgeLimits.maximumFacts`, newest first:

| What | Slots |
|---|---|
| Birds' pronouns and which room they are logged into | 8 |
| House sensors: power, humidity, pressure, temperature, PM2.5, light, wind | 7 |
| Forecasts, highs and lows beside the summaries that say them | 6 |
| Birds' sighting notes | 4 |
| TV, receiver, front door, April's presence | 4 |
| Something April told them | **1** |

The flight facts reached her only through the new retrieval, beside the thirty. Filing what the
birds learned (#229) makes each learned fact better, but the page is filled by recency, and the
newest facts are always sensors.

## The change

The page is built in three parts, and only the third is capped:

1. **The stage, beside the thirty.** `presence.region` (who is in the room) and
   `identity.pronouns` are what the agent builds "Here now: Beaky, Mango (he/him)" and every
   name from; it never writes them as lines (`FactPhrasing.isUnspoken`). They ride on the page,
   uncapped and never counted. (Pronouns already did, for subjects the page names.)
2. **State, folded, beside the thirty.** Each subject's `environment.*` readings are one
   `environment.now` entry; its `forecast.*` one `forecast.outlook`:
   - `place:outside · environment.now = "temperature 51.7°F, humidity 89%, light 0 lux,
     wind 0 mph, PM2.5 2.7 µg/m³, pressure 1010.3 hPa"`
   - `place:outside · forecast.outlook = "today: Partly Cloudy, high 64°, low 50°; tonight:
     Mostly Clear; tomorrow: Partly Cloudy, high 70°, low 50°"` - the `*_f` numbers dropped
     where a summary already says them.
   - A folded entry is made for the page and never stored: `derived_from` lists the readings,
     so Why? still walks to them; it is as new as its newest reading and lasts as long as its
     shortest.
   - Their meanings are in the glossary like every kind's.
3. **The thirty: everything else**, newest first, as before - now what the birds learned, the
   door, the TV, April's presence, sightings - plus the calendar, the retrieved learned facts,
   and the memories, as today.

Agent: another bird's `presence.region` is no longer a line either (only its own was); "Here now"
says who is in the room.

Mango likes the light's trend (April, while this was built): `environment.light_trend` rides
with the light itself - "light 120 lux, dimming" - and `environment.now`'s meaning carries the
trend's ("dimming in the evening is nightfall, at midday a cloud"), so folding loses none of it.

## Measured

Before: the table above, 1 of 30 learned. After deploy: the same question, the same count, in
`query_character_perspective`, and the World Viewer's **Page** panel: pick a bird, type what
April says, and the page is shown as the bird gets it, counted ("18 learned · 4 state · 2 folded
· ...").

## A fuller page (#232; World `0.51.0`, agent `2.91.0`, Viewer `0.13.1`)

Beaky's page after `0.50.0` held 17 things April had told the birds - and, read whole, more
waste:

1. **A memory's meaning, once per memory.** The glossary keeps memory kinds by family
   (`memory.episode`); each memory has a predicate of its own
   (`memory.episode.beaky.2026-10-15.6`), so the agent found it unknown and wrote the family's
   meaning into the uncached moment for every memory, every call. Now meanings are looked up
   by family (`CharacterMind.byFamily`).
2. **A memory, once per subject.** An episode is filed on each subject it is about; three
   copies of one evening took half of the six episodes. Now each memory is handed over once
   (`PresentWorldKnowledge.oneOfEachMemory`, the person's copy first), before the budget is
   counted, and retrieval skips a memory already on the page.
3. **Beliefs cut mid-word.** `MemoryJob` cut at 400 characters ("…She is touched that I write
   ", "…Public"). Now a belief or episode ends at its last whole sentence, 700 at most
   (`MemoryJob.clipped`), and the beliefs prompt asks for four sentences, under 600 characters.
   Beliefs are rewritten nightly, so they heal by the next morning.
4. **The calendar, four lines an event.** Now each event is one `calendar.event` ("Church -
   Sunday, October 18 at 9:30 AM - at Unitarian Universalist Congregation, Freeland - on the
   Home calendar"), each reminder one `reminder.item`, folded like the sensors and never stored.

Also: a forecast's `next_rain` reads "next rain", and the Viewer's Page panel files a folded
event under Calendar.

Held back, one change at a time: the birds' `sighting.identified` kept with `today` (four of
them on the page near midnight) - a learning-contract change of its own.

## Not in this change

- Applying the librarian's filing (#229 Ship 2), which makes the learned facts that now get the
  slots fuller.
- A budget among the thirty (people present first, then places): measure this first.
- Sightings: four slots tonight, each correct and short-lived; left alone until measured again.
