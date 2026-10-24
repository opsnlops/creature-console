# The night lands by morning, and never costs the next one (#262)

On 2026-10-23 Caroll's memories of the 22nd hadn't landed by 5 PM. Her batch was submitted at
3:30 AM and came back at 5:20 PM. Nothing had failed. The chorus's memory model moved to
gpt-6.1-sol on 10-18 (April: "I moved them because Sol is much cheaper"), and its batches went
from minutes to an hour, then to 11–14 hours from 10-22. Beaky's, on gpt-6-astra, take two
minutes. So the chorus stays on Sol, and the lateness is fixed in code.

## What lateness costs

A bird with no memory of yesterday spends the day without it. On 10-23 Caroll spoke 29 lines
before her memories of the 22nd landed (all of her day), Mango 19 of 31, and Kenny 11 of 15.

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
