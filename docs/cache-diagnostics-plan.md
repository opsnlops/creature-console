# Prompt cache diagnostics in Honeycomb (#275) — built: agent 2.108.0

April, 2026-11-02, during the Bears game: "Let's light up those diagnostics in Honeycomb so we
can make better decisions."

The token-cost work (#235, #245) has measured what each call reads from OpenAI's prompt cache
(`cached_tokens`) and writes to it (`cache_write_tokens`), but never *why* a call missed.
`probe-cache` was built to guess, one knob at a time. OpenAI now says why
([prompt cache diagnostics](https://developers.openai.com/api/docs/guides/prompt-caching/diagnostics)).

## What the provider gives

- **Request:** `prompt_cache_options.comparison_response_id`, naming an earlier response.
- **Response:** `prompt_cache_diagnostics` carries:
  - `type`: `cache_hit`, `cache_miss`, `comparison_response_not_found` (the record is gone; it
    expires after a short while) or `unavailable`
  - on a miss, the first `reason`: `model_changed`, `prompt_cache_key_changed`,
    `service_tier_changed`, `tools_changed`, `text_format_changed`, `reasoning_effort_changed`,
    `verbosity_changed`, `context_compacted`, `input_changed`
  - `cache_missed_tokens` and `comparison_reusable_tokens`, both estimates
- **Streaming:** the diagnostics arrive on `response.completed`.
- **Limits:** Responses API, GPT-5.6 and later, so every bird qualifies.
- **Cost:** free, adds no rate-limit load, compatible with zero data retention, and never
  changes the output.

## The design (creature-agent 2.108.0)

1. **What a call compares with.** Each mind's `OpenAIClient` holds a `CacheComparisons` actor:
   its last response id per call kind (question, scene, house). Each kind has its own contract,
   so each is its own cached prefix. A live call sends the previous same-kind id as
   `comparison_response_id`. A tool round compares with the round before it, so a cache broken
   between rounds shows up too.
2. **What doesn't.** The nightly memory calls are different prompts each time, and mostly
   batched, so they compare with nothing.
3. **Where it lands.** `prompt_cache_options` already carries `mode: explicit` (#235), and the
   comparison id joins it. `prompt_cache_diagnostics` is read into `OpenAIResponseSummary`,
   streamed or not. April: "Use whatever attributes match the OTel GenAI spec".
   - **What the spec has.** Semconv 1.41.0 names the cache's token counts,
     `gen_ai.usage.cache_read.input_tokens` and `gen_ai.usage.cache_creation.input_tokens`,
     which are already on every span. It has nothing for a diagnosis.
   - **How these are named.** The spec's way with a provider's own fields is the API's field
     name under `openai.request.` / `openai.response.`, as in `openai.response.service_tier`.

   So the `chat {model}` span carries:
   - `openai.request.prompt_cache_options.comparison_response_id`: the `gen_ai.response.id` of
     the call it was compared with, one hop to that span
   - `openai.response.prompt_cache_diagnostics.type`
   - `openai.response.prompt_cache_diagnostics.reason`
   - `openai.response.prompt_cache_diagnostics.cache_missed_tokens` (int)
   - `openai.response.prompt_cache_diagnostics.comparison_reusable_tokens` (int)

   The `LLM usage` log line carries the diagnosis and the reason as text, under its own
   `llm.usage.*` names, so the span columns stay numbers.
4. **`probe-cache --compare`.** Each round after the first compares with the one before it and
   prints the diagnostics, on both the hand-built path and `--like-mind`.
5. **Honeycomb, after a day of traffic.** A board with:
   - count by `openai.response.prompt_cache_diagnostics.type`, by `creature_agent.call_kind`
     and `gen_ai.agent.name`
   - the `SUM` of `cache_missed_tokens` by `reason`: the dollars question
   - `cache_read` against `cache_creation` input tokens, from the spans already there
   - requested against returned service tier

## What it should settle

- **Service tier.** Does the requested tier come back as asked? A mismatch shows as
  `service_tier_changed` on every call.
- **Tool rounds.** Do they stay cached? "Ten tools cached on round two and missed on round three"
  was fixed by sorting keys; this would show it holding.
- **Expiry.** How often a bird's previous same-kind call has expired before it speaks again, which
  decides whether `prompt_cache_retention` is worth raising.
- **Remaining misses.** The tokens lost to `input_changed`, and so how much a different prompt
  layout could still save.

## Tests

- The parser reads `prompt_cache_diagnostics` from a body and from `response.completed`.
- The request carries `comparison_response_id` beside `mode: explicit`, and only when there is
  one.
- `CacheComparisons` keeps one id per kind, and the night compares with nothing.
- A streamed call against a local endpoint sends the previous same-kind id, and the next call
  sends this one's.
