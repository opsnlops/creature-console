# Places the birds learn from April (#248)

April: "I'm wondering if we could store GPS coordinates on the place entities and then do some
MongoDB magic to return to the birds the location where I most likely am." Of three ways to
learn where places are (Home Assistant zones, the Bridge's calendar locations, April telling a
bird), she chose the third: "That'd be fun."

So a bird learns April's places the way a friend would. She says "Beaky, I'm at the dentist";
the World pins `place:dentist` to where her phone is right now. Next time her phone is there,
the birds know where she probably is, without being told.

## Today

- creature-house hears `person.april` live over Home Assistant's event stream, attributes and
  all (`HomeAssistantStream`, `HouseTranslator`), but casts only home or away (`person.arrived`
  / `person.left` → `presence.state`). The coordinates never reach the World.
- A bird learns with `[learned: subject | predicate | value | expires]` (`Learning.swift`). The
  subject is resolved by `EntityNames` (and the kind judge for a bare name). The value is always
  text. The World stores it as `reported`, with origin `mind:<bird>`.
- No `place.*` or location kinds exist. `presence.location` appears only in a comment.

## The design

1. **The house tells the World where April's phone is (house 0.5.0).** For a mapped `person.*`
   it reads `latitude`, `longitude` and `gps_accuracy`. When the fix moves more than 25 m, or its
   accuracy changes a lot, it sends `person.located` with them. The World keeps one fact,
   `person:april location.gps` = `{lat, lon, accuracy_m}`, observed and valid for 30 minutes (a
   stale fix places no one). The kind is **world-only**: no bird ever sees a coordinate.
2. **A bird teaches a place (agent 2.102.0).** The learning contract gains one line: when April
   says where she is right now, "[learned: person: April | presence.place | place: the dentist |
   2h]". A value that names an entity ("place: the dentist") is resolved like a subject and cast
   as a link (`place:dentist`), the same shape as `calendar.with = person:jesse`. The bird judges
   what she meant; nothing parses "I'm at".
3. **The World pins it (World 0.60.0, `PlaceTeachingRule`).** On a `presence.place` from a mind
   whose value is a place, if April's fix is under 10 minutes old and accurate to 100 m, the World
   casts `place:dentist place.geo` = GeoJSON point + `radius_m` (75 m, or her fix's accuracy if
   that is larger), world-only. Taught again later, the point becomes the running mean of the
   fixes, and the radius grows to cover them. With no fresh fix, the bird's fact stands as it is
   today and nothing is pinned.
4. **The MongoDB magic.** A fact saved as `place.geo` also carries a `geo` field (as facts carry
   `search_text`), with a sparse `2dsphere` index on it. On each new fix, `PlaceInferenceRule`
   runs `$geoNear` from April's point over the current `place.geo` facts. The nearest place whose
   radius plus the fix's accuracy reaches her becomes `person:april presence.place =
   place:dentist`, *inferred*, with a confidence from distance against radius, and its own
   "since". Out of every radius, the inferred fact ends. It recasts only when the answer changes.
   A told `presence.place` (reported, 2 h) and an inferred one share the predicate: the newest
   wins, and arriving home already ends every `presence.*`.
5. **The birds get the place, never the point.** `presence.place` rides on the page like any
   fact about April: "April is probably at the dentist, since 2:10 PM (inferred)". The birds work
   out what it means ("she's at the hangar again").
6. **The Viewer shows it (Viewer 0.19.0).** A Places panel: a map (SwiftUI `Map`) with each taught
   place as a circle of its radius, who taught it and when, April's current fix, and her inferred
   place with its confidence. Coordinates are shown to April here, and only here.

## Slices, one deploy at a time

Slice 1 is built: house 0.5.0, World 0.60.0, Viewer 0.19.0. Home Assistant's `person.april`
carries `latitude`, `longitude` and `gps_accuracy` from the Companion app (`source:
device_tracker.april_s_phone`). It also merges a UniFi network tracker, which gives no
accuracy, so the house takes a fix only when `gps_accuracy` is there. A fix every 10 minutes
while she sits still keeps the 30-minute fact alive.

1. House `person.located` → `location.gps` (world-only); the Viewer's map shows her fix. Check:
   the fix arrives and moves when she does; no bird's page or tool ever carries it.
2. Teaching: the contract line, links as values, `PlaceTeachingRule`, `place.geo`, the taught
   places on the map. Check: "I'm at the …" pins a place where she is.
3. Inference: the `geo` field, the `2dsphere` index, `PlaceInferenceRule`, `presence.place`
   inferred. Check: back at a taught place, the birds know without being told.

## Not yet

- Distance from home when she is at no known place ("about 12 miles out").
- Places from Home Assistant zones or the Bridge's calendar locations.
- Speed or history ("passing the airfield at 60 mph is not being at the airfield").

## Versions

House 0.5.0, World 0.60.0, agent 2.102.0, Viewer 0.19.0, over three slices.
