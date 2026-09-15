# The Information Bridge — What April's Mac Knows, the World Learns

**Status:** Plan written 2026-09-14 evening, after the judgement-and-memory plan shipped (World
`0.24.0`, agent `2.72.0`, Viewer `0.6.2`, all on prod). Nothing built yet. This is the plan
before the code, as the judgement plan was.
**Why:** April, 2026-09-11: "The information bridge is when things get interesting because Beaky
can start learning from things like my text messages." And the founding moment, 2026-09-13: "The
whole reason I went down this path is because I wanted Beaky to be able to say 'April, the robot
parts are here!' because she can see that robot parts are out for delivery from my email."
**Ground it stands on:** facts as facts and the glossary (`fact_kinds`), `facts.given` with
provenance and expiry, learned tags and Forget, the nightly memory, `EntityNames` and its kinds
(`person`, `place`, `house`, `character`, `thing`). The Bridge is a new *source* for a world that
already knows how to hold, show, forget, and remember facts. It is not a new world.
**Design:** [`beakys-world.md`](beakys-world.md) §6 (the original architecture: `creature-scribed`
+ Creature Scribe, the on-device distillation pipeline, the source and privacy protocols) — still
right in shape; this plan orders and narrows it into slices we can ship and see.
**Runs on:** April's M1 MacBook Pro (48 GB), freed when the birds moved to OpenAI. Logged in as
April, app running, lid closed. macOS 27, Apple Foundation Models on-device.

## The moment

Tuesday. At 9:12 a UPS mail lands in April's inbox: "Your package is out for delivery." The
Bridge, on the Mac, reads it under Mail's own permission, recognises a delivery notice, and asks the
on-device model for one small structured thing: carrier, what, when. It remembers that an order
confirmation a week ago called the same tracking number "servo kit (×4)". It casts one fact to the
world — `house:aprils-nest · delivery.expected = "robot parts (UPS), today"`, expiring at midnight,
derived from `bridge:mail` — and throws the mail's text away. The mail itself never leaves the Mac.

At 2:10 the driveway camera sees a truck. The world opens a scene; Beaky is handed the fact and the
happening. "April, the robot parts are here!" — before April looks up from the workbench. Nobody
wrote that line, and nobody wrote a rule that a truck plus a delivery fact makes that line.

The second moment is quieter and comes from the calendar: "Jesse — deck boards, 2 PM Thursday" at
the house becomes `person:jesse · visitor.expected = "Thursday 2 PM, deck boards"` by a world rule,
so when the truck turns in on Thursday Beaky has a name for it. And the third is a text from Polly
— "running late, there by 6" — which is the most private source and therefore last.

## Principles

**"The virtual world can guess, but the real world knows."** The Bridge is the real world
reporting. It casts what a message *says*, never what the message *implies*: "out for delivery" is
a fact; "April will be excited" is not the Bridge's business.

1. **Privacy is a wall, not a policy.** Raw mail, texts, contacts, calendar bodies stay on the
   Mac. The world, the Viewer, and every model that is not on the Mac see only distilled facts. The
   on-device model does the reading; when it is unavailable, the source degrades and waits — it
   never falls back to a cloud model with raw content. Nothing raw goes in a log or a span.
2. **Facts, with provenance and expiry.** Every Bridge cast is a `facts.given` with source
   `bridge:<source>` and `source_event_id` = the item's stable id, so redelivery is a no-op and
   April can Forget any of it. Most Bridge facts expire (`valid_to`): a delivery is today's, a
   visitor is Thursday's, a contact's phone number is until it changes.
3. **The Bridge reports; the world reduces; the mind judges.** A calendar event at the house
   becoming `visitor.expected` is a world rule, deterministic and testable — not the Bridge's
   guess and not the model's. What a fact *means* to a bird is the glossary's job, as today.
4. **Entities are hubs.** `person:jesse` accrues facts from every source — April's words, the
   address book, the calendar, the camera correction. A fact whose value is an entity id is a
   link (`calendar.with = person:jesse`); the world follows links one hop when it gathers what a
   mind is handed. No lookups on the live line — first-sentence latency is still the metric.
5. **Audience.** `fact_kinds` gains an `audience`: `minds` (handed to birds, the default) or
   `world` (kept, shown in the Viewer, used by rules, never put in a prompt). `contact.phone` is
   `world`. Beaky does not need Jesse's number to know he is expected.
6. **The Bridge is a signed macOS app.** TCC permissions (Mail, Messages, Contacts, Calendars,
   Full Disk Access if needed) are per app; a Linux daemon cannot have them. It must keep working
   with the window closed and after a reboot.
7. **Viewable.** Every Bridge cast is on the timeline with its source; every entity has a page;
   the Bridge itself has a health line in the Viewer (last item seen per source, outbox depth,
   model availability). Done means April can see it in the Viewer and in the Bridge's own window.
8. **Small slices, each with a moment.** Contacts first (cheap, deterministic, makes people real),
   then the calendar (visitors), then mail (the founding moment), then Messages (last).

## What the world already gives us

- `facts.given` → `GivenFactReducer`: subject, predicate, value, epistemic state, `valid_to` or
  `valid_for_seconds`, provenance to the event. The Bridge needs nothing new to cast a fact.
- Deduplication by `source.id` + `source.source_event_id`: at-least-once delivery is safe.
- `fact_kinds`: the Bridge seeds meanings for its predicates on first run, exactly as the world
  seeds its own catalogue; April rewords in the Viewer and her words win.
- `EntityNames` and the five kinds. The Bridge writes ids, not names — it knows who it means.
- Retention never touches facts without `valid_to`; Bridge facts carry their own.
- The Viewer: Facts, Meanings, Forget, the timeline. An entity page is the one new surface.

## Step 1 — The wall and the hub (world + Viewer + an empty Bridge)

Before any source: make the world ready to receive, and the Bridge able to deliver nothing.

**World (`0.25.0`):**
- `fact_kinds.audience` (`minds` | `world`), default `minds`; migration v11 backfills. The
  knowledge gatherer (`PresentWorldKnowledge.currentFacts`) drops `world`-audience facts before
  they reach a percept or an offer; `GET /v1/facts` still returns them. `PUT /v1/fact-kinds/{p}`
  accepts `audience`.
- **Links, one hop.** In `currentFacts(about:)`, after `surroundings(of:)`: for every fact about
  the subjects whose value is a string that parses as an `EntityID` of a known kind, add that
  entity to the subjects (once; no second hop). Cheap: one extra query; capped by the same page.
- `GET /v1/entities/{id}`: the entity's current facts (all audiences), the facts elsewhere that
  link *to* it, and its recent events — the entity page's one call. Also what the nightly memory
  job and a solo "who is Jesse?" can read.
- Source kind `bridge` alongside `home-assistant`, `mind`, `person`, `world`, `world-timer`.

**Viewer (`0.7.0`):**
- Entity page: click a subject anywhere (Facts, Timeline, Scenes) → its facts grouped by source,
  links in and out, memories about it, recent events. Wizard actions: Forget, reword.
- Meanings gains the audience toggle.

**Bridge (`Information Bridge` app, `0.1.0`, in this repo under `Information Bridge/` + a
`CreatureBridgeCore` package target for the testable parts):**
- A menu-bar app with a window: sources (all off), world URL, a "cast a test fact" button that
  sends `house:aprils-nest · bridge.hello = "…"` (valid 60 s) through a real outbox.
- The outbox: SwiftData, at-least-once, retry with backoff, visible depth; checkpoints per source.
- Health facts about itself: `thing:information-bridge · bridge.source.<name> = ok | degraded |
  off`, cast on change, audience `world`. The Viewer shows the Bridge as an entity.
- Signed, launch-at-login, survives lid-closed and reboot. No TCC prompts yet.

**Moment:** the test fact appears on the Viewer timeline as `bridge:app`, and Forget removes it.

## Step 2 — Contacts: people become real

**Source:** the Contacts framework (TCC: Contacts). Deterministic; no model.

**Facts on `person:<slug>`:** `contact.phone` (`world`), `contact.email` (`world`),
`contact.birthday` (`minds` — birds may know a birthday), `person.relationship` (`minds`; from
the card's "related names" or April's own labels: "sister", "contractor"), `contact.address`
(`world`). Each with `derived_from` the contact's identifier; `valid_to` none (until changed).
A changed card re-casts; a removed one retracts.

**Entity resolution — April decides, once.** A contact becomes a world entity only when April maps
it, in the Bridge's window: "Jesse Alvarez → `person:jesse`". Unmapped contacts are never cast.
The map lives on the Mac (and is the same map Messages and Calendar use in later steps). This is
the single rule that keeps four hundred contacts from becoming four hundred half-known people.

**Why first:** it makes `person:jesse` a hub with something on it before any calendar or text
mentions him, it is the cheapest source to get right, and the audience mechanism gets exercised
on the facts that most need it.

**Moment:** "Beaky, who is Jesse?" → "Your contractor, April" — from a `person.relationship` fact
the Bridge cast, not one April typed. The Viewer's entity page for Jesse shows phone and email in
grey (world-only) and relationship in the normal colour (minds).

## Step 3 — Calendar: visitors and errands

**Source:** EventKit (TCC: Calendars), allowed calendars chosen in the Bridge. Deterministic; a
small on-device extraction only for free-text titles when needed ("Jesse deck 2pm" → who, what).

**Entities and facts:** each event within the horizon (default: the next 7 days) is
`event:<calendar-item-id>` with `calendar.title`, `calendar.starts`, `calendar.ends`,
`calendar.location`, `calendar.with = person:jesse` (a link, when an attendee or the title
resolves through April's map), all `minds`. Cancelled → retracted. Rescheduled → re-cast.

**World rule (deterministic, `0.26.0`):** an `event:*` at the house (location matches, or no
location) with `calendar.with = person:X` starting within 24 h → `person:X · visitor.expected =
"<when, in human words>, <title>"` valid until the event ends + 2 h. A reducer, tested like
`HouseSceneRequests`. The same predicate April's learned tags already use, so nothing downstream
changes: the truck on Thursday finds Jesse expected exactly as if April had said so at lunch.

**Timers:** the world's own timer service (`calendar-event-<id>:starts` already exists in the
design) fires `calendar.starting` 15 min before: a consideration for the lead ("April's dentist is
in fifteen minutes" — she may say it or not, quiet hours apply).

**Moment:** Thursday 1:58, the driveway camera: "April, that's Jesse's truck — deck boards at
last?" with nothing typed all week.

## Step 4 — Mail: the founding moment

**Source:** a MailKit extension or a Mail rule that hands selected messages to the Bridge (TCC:
Mail via the extension; the Bridge never reads the mailbox directly). Only mail matching cheap
deterministic pre-filters reaches the model: sender domains and subject patterns for carriers
and merchants April lists (UPS, FedEx, USPS, Amazon, Adafruit, DigiKey, Prusa…). Everything else
is `classified_irrelevant` and forgotten.

**Extraction (on-device):** Foundation Models guided generation into two small types —
`CommerceObservation` (order id, merchant, items as April would say them, tracking) and
`ExpectedArrival` (carrier, tracking, window, "out for delivery" / "delivered"). Each field marked
present-in-source or inferred; only present-in-source fields may become facts. Model unavailable
→ source `degraded`, items wait, nothing is sent elsewhere.

**Correlation (deterministic, on the Mac):** tracking number joins arrival to order, so an
anonymous "1 item out for delivery" becomes "robot parts (servo kit ×4)". Order facts live on the
Mac only until they are joined or expire (30 days); they are not cast.

**Facts:** `house:aprils-nest · delivery.expected = "robot parts (UPS), today"` (`minds`, valid
until midnight local), `delivery.arrived` when the carrier says so (valid 6 h) — and the camera's
truck lets Beaky say it first. `derived_from` = `mail:<message-id>`; the message id, never the
message.

**World:** nothing new — `delivery.expected` and `delivery.arrived` are glossary entries the Bridge
seeds. The judgement plan's principle 3 does the rest: the truck is a happening, the delivery is
a fact, Sol puts them together.

**Moment:** the one in the first paragraph. This step is done when it happens unscripted.

## Step 5 — Messages: last, and by allowlist

**Source:** the Messages database (`chat.db`; TCC: Full Disk Access) read-only, or the supported
automation path if macOS 27 offers one — decided when we get here. Only conversations April
allowlists in the Bridge (by mapped person) are read at all; group chats off by default.

**Extraction:** one type, `SocialCommitment` — who, what, when, where — from a message *to
April* by a mapped person, present-in-source fields only. "Running late, there by 6" from Polly →
`person:polly · visitor.expected = "tonight around 6"` (valid until 9 PM). Nothing else: no
sentiment, no summaries, no "April said". April's own outgoing messages are never read.

**Moment:** the door unlocks at 6:04; "That'll be Polly, April — she said around six."

## What the Viewer shows, per step

| Step | Viewer |
|---|---|
| 1 | Entity page; audience in Meanings; the Bridge as an entity with source health; `bridge:*` on the timeline |
| 2 | People with contact facts greyed (world-only); relationship in the normal colour |
| 3 | `event:*` entities; `visitor.expected` with `derived_from` the calendar event; the reducer's decision on the timeline |
| 4 | `delivery.expected` on the house; the scene where the truck met it |
| 5 | `visitor.expected` from a text, showing only the person and the source kind |

## What the Bridge shows, in its own window

Sources and their health; permissions with the fix for each; April's contact→entity map; calendars
allowed; the merchant/carrier list; the Messages allowlist; the outbox; a redacted inspector of the
last N *facts* sent (never the sources); a "cast a test fact" button; model availability. Vim-free.

## Versions

- Step 1: World `0.25.0`, Viewer `0.7.0`, Bridge `0.1.0`.
- Step 2: Bridge `0.2.0`; glossary seeds only.
- Step 3: World `0.26.0` (visitor reducer, calendar timers), Bridge `0.3.0`.
- Step 4: Bridge `0.4.0`; glossary seeds only. Tag the day the sentence is said.
- Step 5: Bridge `0.5.0`.

Each step: docs (this plan's status line, `beakys-world.md` §0, a `docs/information-bridge-manual.md`
started in step 1), tests (a deterministic fake distiller; the world's reducers under the black-box
suite), and the Viewer surface, in the same commit.

## Open questions for April

1. **Which Mac, exactly, and who is logged in?** The plan says the M1 MacBook Pro, lid closed, April
   logged in. Does it sleep? (Amphetamine / `caffeinate` / power settings are part of step 1.)
2. **Contact mapping:** a manual map in the Bridge (this plan) — or should a contact with a
   `person:*` already known to the world (Jesse, Polly) be matched by name automatically and only
   *new* people need a decision?
3. **The calendar horizon** (7 days?) and which calendars. Does "April's dentist" belong in Beaky's
   mouth at all, or only visitors-to-the-house?
4. **Merchants and carriers list** for step 4 — start with the ones from the last month of mail?
5. **Messages access path:** `chat.db` under Full Disk Access is the known-working way; is that
   acceptable on this Mac, or wait for a sanctioned API?
6. **Audience granularity:** two levels (`minds` / `world`) or three (add `lead` — only Beaky)?
   Two is enough for the plan; three is a small change later.
7. **Does the Bridge get a bird?** It is an entity (`thing:information-bridge`) with health facts.
   It does not speak. Unless you want it to.
