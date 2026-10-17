# Token costs (#235)

April: "Creature World is looking to be around $200/mon in tokens and I'd like to save what we
can." The full survey and plan are on #235; one change at a time, measured.

1. **Measure cache writes (agent 2.96.0).** Each chat span carries
   `gen_ai.usage.cache_creation.input_tokens` (OpenAI's `input_tokens_details.cache_write_tokens`,
   billed at 1.25x) beside `gen_ai.usage.cache_read.input_tokens`, plus the matching
   `gen_ai.client.inference.usage.cache_creation.input_tokens` metric and the usage log line.
   A day of this is the "before" number.
2. **Explicit cache points, and the chorus shares (agent 2.97.0).** Built as one change from the
   baseline and the probes of 2026-10-17:
   - `prompt_cache_options.mode: explicit` on every request. Only marked parts are written: the
     stable item's two parts (what every bird on a model shares - contract, house scenes,
     glossary - then this bird's persona) and the conversation so far. The moment and a night's
     memory are no longer written; overnight, the memory alone wrote 579k tokens at 1.25x that
     were never read.
   - The shared part goes first and the persona after it, in one developer message with two
     content parts (the shape the probe proved).
   - `prompt_cache_key` is the model, not the bird. Caches cross API keys within the org, so the
     per-bird keys (and per-bird billing) stay; the per-bird cache key is what blocked sharing.
   - Probed live with this layout: Mango wrote 4,997; Kenny, on another key, read 4,632 and wrote
     only his 365-token persona; Mango again read all of it and wrote nothing. The moment was
     uncached at 1x each time, never written.
   - `llmCache.explicit: false` restores the old way.
   - Measured live after deploy (2026-10-17, ~60 calls): every warm call wrote 0 and read
     ~6.6k; the chorus's cold start was Kenny writing 6,621 and Caroll and Mango reading 6,112
     each, writing only their personas. Roughly 15% off a warm call, 40% off a cold chorus
     start, 20% off the memory. The rest, ~5.3k a call, was still sent fresh.
3. **What a bird knows, in layers (agent 2.98.0; the cache points removed in 2.98.1).** Measured
   live: every scene call after the deploy wrote 3.5-4.6k and read only the stable 6.6k. Both
   layers depend on the scene's words - recalled memories (`retrievedInPrompt`), facts the words
   call up (`factsRetrievedInPrompt`), the facts on whoever is mentioned - so each scene changed
   them; the test used a fixed fact list. Also wrong in the 2.98.0 notes: the reported layer is
   never shared between birds, since it comes after each bird's own persona and memories.
   Originally: The moment opened with the clock, so
   nothing after it could be cached. Now, before the moment:
   - the bird's own memories (`remembered`, fixed until the 3:30 AM run), a cache point, read
     on every call that day;
   - what the world was told (`reported`: learned facts, the calendar, the forecast), oldest
     first so a new fact joins the end, a cache point, read by the next birds in a scene.

   Then the moment: the clock, what the house observes, what just happened, the bird's recent
   lines; then the script. In a conversation the turns so far keep the fourth cache point and
   the reported layer rides uncached. Every time is a timestamp - "since Oct 16, 9:03 PM",
   "8:03:05 PM: the front door was unlocked" - never "(5 minutes ago)"; April: "a frontier
   model can determine 'about ten minutes ago'."
4. Warm-ups, if cold calls still dominate after this.
4. A cost board in Honeycomb.

Side note held for later: the glossary sends the world-only kinds' meanings too.

## Review, 2026-10-17: where the money goes

Prices from OpenAI's pricing page (per 1M tokens; cache reads 0.1x, writes 1.25x of input):
gpt-6-astra $10 in / $50 out; gpt-6.1-sol $2 / $10; gpt-6-luna $0.10 / $0.50. **Fast tier is
2x** (every bird runs `service_tier: fast`); **Batch is 0.5x** (the nightly memory).

| Spend (~40 h of traffic, scaled to a month) | ≈ / month |
|---|---|
| Nightly memory, Astra, batched (episodes, beliefs, librarian) | **~$135** |
| Beaky's scenes, Sol, fast | **~$105** |
| Beaky's house remarks, Sol, fast | ~$32 |
| The chorus, Luna, fast | ~$14 |
| **Total** | **~$285** |

Today's cache work was measured in tokens, and most of it landed on Luna, which is a hundredth
of Astra's price. In dollars it helps mostly through explicit mode on the nightly memory (no
more 1.25x writes, from tonight) and the shared stable part.

### The nightly memory (~$135)

Per night (2026-10-17 run): the episode stage sends **~98k tokens per bird, nearly identical
across the four birds** (392k); the belief stage 20-58k per bird (168k) and writes ~8k of
output each (~$0.70 at $25/M); the librarian 17k. In the prompt the persona comes first and the
day's record after it, so the four copies can never share a cache.

What a day's record holds (2026-10-16, JSON): 1,038 happenings, of which 951 are `facts.given` -
287 are `bridge:app` status facts (73k chars) and ~275 are the birds' own memory writes from the
night before; a `learned` list (664 items, 188k chars) that repeats those same `facts.given`;
74 forecast updates (in both lists); and 105 scenes whose 230 lines are all also in the
conversation.

1. **Trim the day record** (World `days/:day`, or the agent's rendering): drop `bridge:app` status
   facts and the memory writes, render `facts.given` once, render scene lines once (the scene's
   trigger and lines; the conversation keeps only what no scene holds), keep the last value of
   each forecast. Likely ~98k → ~35-45k a bird: **~$30/month**, and less noise to remember from.
2. **Share the record across the four birds**: the record first as a cache point, the persona and
   instructions after it. Only pays if Batch requests read each other's cache; the four birds
   submit their batches at the same moment, so they may all miss and each pay the 1.25x write.
   **Probe first** (two batch requests in sequence, and two at once). If it works: ~$10-15/month.
3. **The belief stage every night** re-reads 30 days of episodes and rewrites every belief
   (~$1.60 a night with its output). Weekly, or only after enough new episodes: **~$40/month**.
   April's call.
4. **The memory model.** Astra is 5x the price of gpt-6.1-sol, for input and output alike.
   Sol for the episodes (and maybe the beliefs), with Astra kept for the librarian: **~$80-110 a
   month**. A quality decision, April's.

**Done (#242, World 0.57.0, agent 2.99.0):** item 1, the trim. On 2026-10-16's record: ~98k
→ ~19k tokens a bird (82%), ~316k fewer Astra tokens a night.

### Beaky (~$137)

5. **The fast tier doubles everything.** House remarks are background announcements; standard
   tier halves them (**~$16/month**). Beaky's scenes on standard would save ~$50/month at some cost
   in first-sentence latency, so measure first. The chorus on standard saves ~$7.

   **Benchmarked 2026-10-17** (15 calls a tier, alternating, ~12k prompt with 6.6k cached,
   reasoning low, streaming):

   | | first token p50 / p90 | whole reply p50 / p90 |
   |---|---|---|
   | Sol fast | 1.01 s / 1.25 s | 1.47 s / 1.71 s |
   | Sol standard | 1.78 s / 2.30 s | 2.76 s / 4.20 s |
   | Luna fast | 0.68 s / 1.23 s | 1.06 s / 1.58 s |
   | Luna standard | 0.61 s / 1.21 s | 0.99 s / 1.64 s |

   Sol on standard adds ~0.8 s to the first word and ~1.3 s to the reply; Luna is the same on
   both tiers. And the cache is per tier: the first standard call missed what the fast calls
   had cached. So the chorus can go to standard for free (halving its cost), and Beaky's
   house remarks on standard would lose the scenes' cache as well as ~0.8 s.
6. **Cold starts.** Beaky's house remarks started cold 21 times in 45 (47%), her scenes 8%. A
   house remark has a different contract (`houseRemarkCore`) ahead of the glossary, so it
   never reads the scenes' cache, and house remarks are too rare to stay warm on their own.
   - Put what every call shares first (glossary, house scenes, the common rules), then the
     persona, then the kind's own contract: a house remark after a scene reads ~5k instead of
     ~3.8k, or nothing.
   - A keep-warm call while the house is active (presence home, outside quiet hours; only when
     the last real call was over ~25 minutes ago): ~11k read at $0.20/M fast is ~$0.002 a ping.
     A cold start writes the same at $5/M, ~$0.05. **~$15-25/month** net, mostly on house
     remarks.
7. **Tool rounds** re-send the moment and the lookup result uncached (Caroll, 16k with 6.6k read).
   A cache point at the end of round 0's input for the rounds after: ~$1-2/month.

### The standing layers (the 2.98.0 lesson)

8. A bird's memories and the reported facts can only be cache points if the World hands the
   standing part (the day's 16 fixed memories, the page's standing facts) apart from what the
   scene's words call up (recalled memories, facts the words retrieve, the people mentioned).
   With that, Beaky's ~4k layers go from $4/M to $0.20/M on most calls: **~$10-15/month**.

   **Building as #245** (docs/standing-page-plan.md; World 0.59.0, agent 2.101.0, Viewer
   0.18.0). Measured 2026-10-17 evening: with everything else done, the fresh ~5.3k is ~90% of a
   Beaky reply (~2.3¢), so this is now the largest lever: ~2.3¢ → ~1.1¢ a reply, ~$10–55/month
   by traffic. The chorus' nights moved to Sol the same day (~$50 → ~$10/month).

### Not worth more work

- The chorus: ~$14/month all told; even perfect caching saves a few dollars.
- The Decisions kind judge: $0.10/M, a few hundred tokens a call.
- The glossary's world-only kinds: cached at $0.20/M.

### Measurement

- A cost column: a Honeycomb calculated field, price × tokens by model, tier and batch, on a
  board by call kind and bird. It turns this review into a number to watch.
- Retype the `gen_ai.usage.*` columns to integer once 2.97.0's log-key fix is everywhere.
