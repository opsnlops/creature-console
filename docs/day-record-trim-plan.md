# Trim the nightly day record (#242, part of #235)

April: "Go ahead and start on 3." Each bird's nightly episode prompt is ~98k tokens on Astra,
nearly the same for all four birds, and most of it is duplication and our own bookkeeping.

## What the record of 2026-10-16 held

| Part | Size (JSON characters) | What it is |
|---|---|---|
| Happenings, `facts.given` | 951 lines, 187k | every one also in `learned` |
| … of which `bridge.online` | 287 | the Bridge's heartbeat, already left out of `learned` |
| … of which the 3:30 AM memory writes | 238 | no summary, rendered "facts.given at the carport" |
| `learned`, memory writes | 488 of 664 lines, 122k | the birds' own memories of the day before |
| `learned`, forecast re-casts | ~80 extra lines | `forecast.next_rain` 19 times, `forecast.tomorrow` 16 |
| Scenes | 230 lines, 62k | every one also in the conversation |

## The change

1. **World, `DayDigestBuilder`** (the record as the nightly memory sees it):
   - happenings leave out `facts.given`: `learned` carries each cast fact once, with who and
     when;
   - `learned` leaves out memory writes (any `memory.*` family);
   - the folded families (`WorldKnowledgeLimits.foldedPrefixes`: `forecast.`, `environment.`)
     keep only each subject and predicate's last value of the day. Everything a mind or a person
     said is kept, every time it changed.
2. **Agent, `MemoryJob.transcript`**: one timeline of what was said, oldest first. The
   conversation's lines; any scene line the conversation doesn't hold; each house occasion's
   trigger in its place ("(the house noticed: the front door was unlocked)"). The separate
   "Scenes in the room" section goes. A scene April opened by speaking is her line, already in the
   conversation.

## Expected

~98k → ~25-35k tokens per bird per night: roughly 280k fewer Astra batch tokens a night
(~$1.40), less if the memory moves to Sol. Less noise to remember from, too. Measured the next
night on `agent.memory.remember`'s chat spans.

## Versions

World 0.57.0, agent 2.99.0.
