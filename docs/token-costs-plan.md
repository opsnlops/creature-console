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
3. Warm-ups, if cold calls still dominate after this.
4. A cost board in Honeycomb.

Side note held for later: the glossary sends the world-only kinds' meanings too.
