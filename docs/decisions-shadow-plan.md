# Decisions API shadow plan

OpenAI's Decisions API (`POST /v1/decisions`, public beta, `gpt-6-luna` only, released
2026-10-07) returns typed answers - a `predicate` probability, a `choice`, a `score` - about ten
times faster than the Responses API, at $0.10 per million input tokens and nothing for output.
April: "I think we could use it."

## The question it could answer

Whether a bird speaks at all. Over the seven days to 2026-10-07 the birds took 998 scene turns
and 320 of them (a third) ended in `chose_silence`: each a full Responses call - persona,
glossary, the scene - of about 1.9 s, to say nothing. A predicate asked first ("does Kenny have
something worth adding here?") could skip those calls.

The risk is a classifier deciding *for* a bird: Mango's best lines are the ones nobody would
predict. So nothing changes yet - the API is asked in **shadow**, and its guesses are measured
against what the birds actually did.

## Shadow mode (this slice, #221)

- Agent config `llmDecisionsShadow: true` (default off) turns it on per bird; `llmDecisionsModel`
  (default `gpt-6-luna`) names the model. Same API key and base URL as the speaking model.
- On every scene turn, alongside the normal call and never in its way, the mind asks one
  predicate, `speaks`: would this bird, as its persona describes it, add something worth saying
  to the scene as it stands - not a repeat of what was said? The input is the bird's persona and
  the scene script the turn is offered.
- The answer is recorded on that turn's `agent.scene_turn` span:
  - `decisions.speak_probability` (0-1), `decisions.duration_ms`, `decisions.input_tokens` when
    reported, `decisions.error` when the call failed or refused;
  - `scene.turn.lead` and the existing `agent.suppression_reason` (`chose_silence` or absent)
    are what it is measured against.
- The decision call waits at most a few seconds after the bird has decided and is cancelled
  past that: shadow work never delays a turn or fails one.
- Direct questions from April (`agent.turn`) are not shadowed: they are always answered, and
  their first-sentence latency is the metric that matters most.

## Reading it (after a few days)

In Honeycomb, on `agent.scene_turn` with `decisions.speak_probability` present: the
distribution of probability for turns that spoke vs `chose_silence`, by bird and by lead/chorus;
for a few thresholds, how many silent calls would be skipped and how many spoken lines would
have been lost (and which - read them). A threshold that loses no line April would miss is the
case for turning the gate on; anything else is the case for leaving it off.

## Not in this slice

- Gating (skipping the Responses call below a threshold): only if the numbers above make the
  case, as its own slice.
- The Bridge's reading of texts and mail: that is on-device so raw messages never leave the
  laptop; sending them to a cloud classifier would break that.
