# The night lands by morning, and never costs the next one (#262)

On 2026-10-23 Caroll's memories of the 22nd hadn't landed by 5 PM. Her batch was submitted at
3:30 AM and came back at 5:20 PM. Nothing had failed. The chorus's memory model moved to
gpt-6.1-sol on 10-18 (April: "I moved them because Sol is much cheaper"), and its batches went
from minutes to an hour, then to 11–14 hours from 10-22. Beaky's, on gpt-6-astra, take two
minutes. So the chorus stays on Sol, and the lateness is fixed in code.

## What lateness costs

A bird with no memory of yesterday spends the day without it. On 10-23 Caroll spoke 29 lines
before his memories of the 22nd landed (all of his day), Mango 19 of 31, and Kenny 11 of 15.

And a slow night costs the next one. A night is two stages, the day's episodes and then the
month's beliefs, and each may wait 20 hours (`llmMemoryBatchWaitHours`). `WorldMindService`
runs one night at a time. A night that arrives while another is still running is skipped
("Still remembering the last day; skipping") and never remembered. That would also drop a day
April asks to be remembered again while a night is still out.

## The change (agent)

1. **The batch is for what nobody waits on.** The episodes stage is asked directly; the beliefs
   stage stays in the batch.
   - One night's tokens, 10-23, for the three chorus birds: episodes 44.6k in and 2.9k out;
     beliefs 148.4k in and 24.0k out.
   - Sol is $2 in and $10 out per million, the batch half that. Episodes asked directly come to
     $0.39 a night against $0.33, about $2 a month more for the chorus, and the memories land
     at 3:31 AM.
   - Beaky's episodes, on Astra, add about $3 a month.
2. **The night is written down before it is asked**, as it already was before a batch. A
   restart then asks again rather than losing it.
3. **Nights wait in line (`MemoryNights`), kept in `memory-nights.json`.**
   - A night that arrives while another is running waits behind it, never skipped.
   - The night in hand stops waiting on the provider while another waits. Its batch is
     cancelled and its stage asked now, and the same goes for the librarian's.
   - At a start the line resumes: the night in progress first (from `memory-pending.json`), then
     the rest.

## Not in this change

Whether the beliefs stage needs to run every night (#235, item 3).

## Versions

Agent 2.104.0, a feature. World and Viewer are unchanged.

## Then: the episodes ride the batch again, for an hour (#264, agent 2.105.0)

That evening, after #263, the 22nd was remembered again, and the chorus's Sol beliefs batches
came back in about three minutes. At 3:30 AM the same model's batches had taken 11–14 hours. So
the slowness depends on when a batch is sent, and a batch is often quick. April asked: "We're
still batching, right? Batching is half the cost."

Both stages ride the batch again. The episodes wait at most `llmMemoryEpisodesWaitMinutes` (60)
from the night's start, the deadline written down with the night so a restart keeps it, and are
then asked directly. They cost half when the batch is quick, and land by 4:30 AM at worst. The
beliefs keep `llmMemoryBatchWaitHours`. A night waiting behind still cuts any wait short.


## Then: a 503 is a look missed, not the end of the night (#268, agent 2.105.2)

On 10-26 and 10-27 the chorus's Sol batches took about 12 hours again. The one-hour cap worked:
their episodes were asked directly at 4:30 AM, and their beliefs waited on the batch. Mango's
beliefs batch was checked once a minute for 11 hours, about 660 looks. One look came back 503
from OpenAI's front door ("upstream connect error or disconnect/reset before headers"), and that
one error ended his night. The fallback asks now only for an `OpenAIBatchError`, and a 503 is an
`OpenAIClientError`, so the beliefs rewrite for the 25th was lost. His episodes and reflection
had landed already, and the next night's rewrite caught him up.

Nothing that calls OpenAI tried again on anything. In 30 days that cost this night and one live
streamed reply (a connect timeout, 10-21).

### The change (agent)

1. **One retry policy for every OpenAI request (`OpenAIRetry`)**, the one OpenAI's own SDKs
   use. A 408, 409, 429 or 5xx, or a connection that failed, is sent again after an
   exponential backoff with jitter, or after the time the provider names in `retry-after-ms`
   or `retry-after`.
   - A bird's reply (`live`): two more tries, about 0.5 s and 1 s apart. A request that ran out
     of time is not sent again, since its moment has passed. A streamed reply is only sent
     again before its first word.
   - The night's work (`night`): eight more tries over about three minutes, timeouts
     included. This covers the direct asks, and the batch's upload, submission, looks and
     output.
   - The Decisions kind judge is a `live` call.
2. **A look at a batch that fails on the way is a look missed.** The wait goes on, a minute
   later, up to its deadline. A look refused for good (a 401, a 404) still ends it.
3. **A batch that fails for any reason is asked now.** The memory job falls back the way the
   librarian already did, so a night is never lost to the batch.

### Not in this change

- A night whose direct ask also fails, with OpenAI down for longer than the retries, is still
  logged and not tried again later.
- The agent's own calls to the World do not retry either.
