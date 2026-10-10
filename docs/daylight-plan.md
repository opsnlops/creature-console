# Daylight: the trend and the dusk moment (#223)

April added `sensor.outside_light_level` (lux) for the birds (#222). Mango pointed out
the gap: *"one bright reading only tells you what the sky is doing now. A threshold plus
a falling trend would catch dusk before it gets properly dark."* April: "let's add both."

## What the birds get

- **`environment.light_trend`** on `place:outside`: `brightening`, `steady`, or `dimming`.
  It compares the newest reading with the oldest one from the last half hour.
  - It lasts 45 minutes and is renewed by every reading, so it lapses when the readings
    stop (all night, at 0 lux) and never lingers.
- **`daylight.dusk`**, a moment: the light falls through 100 lux in the afternoon or
  evening. **`daylight.dawn`**: it rises through 100 lux in the morning.
  - Each happens once per local day, and the noon line keeps a dark storm from passing
    for dusk.
  - Each is a happening in the story and in the nightly digest.
  - The packaged `world.json` makes dusk a house consideration (`consider_on`, hourly
    cooldown), so the lead may remark on nightfall or let it pass. Dawn is recorded but
    opens nothing, since quiet hours end at seven and a winter dawn comes after that.
    One `consider_on` line would change that.

## How

- A world rule, `DaylightRule`, like the delivery and reminder rules. It watches the
  world's stream for `environment.measurement_changed` with `light_lux`.
  - At startup it seeds from the current `environment.light_lux` fact.
  - The arithmetic lives in a value type, `DaylightTracker`, so it is testable without
    Mongo.
- The trend is told as an `environment.measurement_changed` (`light_trend`) with
  `valid_for_seconds`. It is state, not story: measurements never enter the happenings
  and keep short retention.
- 100 lux sits in the middle of the dusk band: an overcast sunset, or a clear one ten or
  fifteen minutes later. Civil dusk ends near 3 lux.
- Quiet hours (23:00–07:00) are already honoured by the scene openers.
