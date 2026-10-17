# Token costs (#235)

April: "Creature World is looking to be around $200/mon in tokens and I'd like to save what we
can." The full survey and plan are on #235; one change at a time, measured.

1. **Measure cache writes (agent 2.96.0).** Each chat span carries
   `gen_ai.usage.cache_creation.input_tokens` (OpenAI's `input_tokens_details.cache_write_tokens`,
   billed at 1.25x) beside `gen_ai.usage.cache_read.input_tokens`, plus the matching
   `gen_ai.client.inference.usage.cache_creation.input_tokens` metric and the usage log line.
   A day of this is the "before" number.
2. An explicit cache point after the stable item, so the moment is no longer written each call.
3. A shared prefix for the Luna birds, if a `probe-cache` test shows caches cross keys in one org.
4. A cost board in Honeycomb.

Side note held for later: the glossary sends the world-only kinds' meanings too.
