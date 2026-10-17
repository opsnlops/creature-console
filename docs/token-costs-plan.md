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
3. **What a bird knows, in cached layers (agent 2.98.0).** The moment opened with the clock, so
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
