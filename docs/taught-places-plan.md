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

## Slice 2 in detail: teaching (agent 2.103.0, World 0.61.0, Viewer 0.20.0)

Planned 2026-10-20, with slice 1 live and #255 shipped (a mind can no longer keep the World's
own kinds, and its glossary no longer shows them).

**The bird (agent).**
- The contract gains: when April says where she is while she is out, keep it on her, the place
  named with its kind - `[learned: person: April | presence.place | place: the dentist | 2h]`.
  The bird judges what she meant ("I'm at the dentist", "made it to the hangar"); nothing in
  code parses "I'm at".
- **A value that names an entity is a link.** A learned value written `<kind>: <name>`, the way
  a subject is named, resolves through `EntityNames` exactly as a subject does, without the kind
  judge: the kind is written. "place: the dentist" is `place:dentist`, or the id the world
  already holds for that name. Anything else stays text ("10:30 AM": "10" is no kind; more than
  four words is no name). The World already treats a value that is an id as a link
  (`WorldFacts.link(in:)`) and follows it one hop onto the page, as for `calendar.with`.

**The World (`PlaceTeachingRule`, on the event stream like the daylight rule).** For a
`facts.given` from a **mind** whose predicate is `presence.place` and whose value links a
`place:`:
- **Where she is now:** the subject's current `location.gps`, at most 15 minutes old (the house
  re-sends a still phone every 10) and accurate to 100 m. Not when the subject's
  `presence.state` is `home`: at the house, the house knows, and a room taught at home
  ("I'm in the workshop") would otherwise claim the house's point. No fresh fix, nothing pinned;
  the bird's fact stands, as today.
- **The pin:** `place:dentist place.geo` = `{"type": "Point", "coordinates": [lon, lat],
  "radius_m", "fixes", "taught_by"}`. GeoJSON order, so slice 3 can index it as it is. Cast as a
  `facts.given` from `world:places` (kind `world`), `inferred`, caused by the teaching event and
  the fix; no end. World-only by nature (`worldOnlyPredicates`): never on a page, in a tool, in
  the glossary, or kept by a mind.
- **Taught again:** within 1 km of the pin, the point becomes the running mean of the fixes
  (weighted by `fixes`), and the radius grows to cover the old circle's shift and the new fix:
  at least 75 m and the fix's accuracy, at most 500 m. Farther than 1 km, the place has moved,
  or was taught by mistake: the newest word wins, and it is pinned afresh.
- Each teaching event pins once (`place:<event id>`), so a replayed event changes nothing.

**The Viewer.** The Places panel draws each taught place as a circle of its radius with its
name, and lists them: who taught it last, when, how many fixes. It shows the map when there
are places and no fix.

**Check:** April, away, says "Beaky, I'm at the …": the bird keeps `presence.place =
place:…`, the place appears on the map where she is, and no bird's page, tool, or glossary
carries a coordinate.

**Tests.** The agent: a tag's `place: the dentist` value is `place:dentist`, a known name is
its id, text stays text, and the contract says so. The World: the pin's arithmetic (first,
again near, moved, the caps); the rule against MongoDB (pins on a fresh fix; nothing for a
stale or vague fix, at home, a value that is no place, or a source that is no mind; a second
teaching moves the mean); `place.geo` is world-only. The Viewer: taught places read from the
facts.

## Not yet

- Distance from home when she is at no known place ("about 12 miles out").
- Places from Home Assistant zones or the Bridge's calendar locations.
- Speed or history ("passing the airfield at 60 mph is not being at the airfield").

## Versions

Slice 1: house 0.5.0, World 0.60.0, Viewer 0.19.0. Slice 2: agent 2.103.0, World 0.61.0,
Viewer 0.20.0. Slice 3: World, and the Viewer's inferred place.
