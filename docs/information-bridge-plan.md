# The Information Bridge — What April's Mac Knows, the World Learns

**Status:** Plan written 2026-09-14 evening, after the judgement-and-memory plan shipped (World
`0.24.0`, agent `2.72.0`, Viewer `0.6.2`, all on prod); revised the same evening after April read
it — WeatherKit first, orders as entities in the world, mail and Messages as sources of what April's
life contains, not only of delivery notices. Nothing built yet. This is the plan before the code,
as the judgement plan was.
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

Some smaller moments the same machinery makes, in the order this plan builds them:

- "Beaky, is it going to rain today?" — "Not until this evening, April; about a quarter inch
  overnight." The house's rain gauge knows the past; WeatherKit knows the next few days.
- "Did I order a servo?" — "Yes, four, from Adafruit on the 9th. They shipped Thursday." The order
  is an entity in the world with a number, items, and a status, from mail the Bridge read.
- "Jesse — deck boards, 2 PM Thursday" on the calendar becomes `person:jesse · visitor.expected` by
  a world rule, so when the truck turns in on Thursday Beaky has a name for it.
- A text from Polly — "running late, there by 6" — and the door at 6:04: "That'll be Polly."

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
   What a source *says* — an order number, a tracking number, a date, a merchant, an item as the
   mail names it — is fine to keep in the world: those are the facts, and April wants to ask about
   them. What a source *is* — the message — is not.
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
8. **Small slices, each with a moment.** WeatherKit first (no privacy, fills a gap the house has
   today, proves delivery end to end), then contacts (makes people real), the calendar (visitors),
   mail (orders and deliveries — the founding moment — and appointments), then Messages (last).

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

## Step 2 — WeatherKit: what the sky will do

**Source:** WeatherKit, for the house's coordinates (Bridge config). No TCC; an entitlement on the
signed app and the developer account. Deterministic; no model. Polled hourly, cast on change.

**What the house already knows** (creature-house from Home Assistant): the present and the past
— `environment.temperature_f`, `humidity_percent`, `wind_mph`, `rain_today_in`, `pressure_hpa`,
`pm25_ugm3`, `power_w` on `place:outside`. Beaky answered "how much rain today" from that. What
nobody knows is what comes next, and the birds sound vague when April asks.

**Facts on `place:outside`** (all `minds`, `valid_to` the end of the period they describe):
- `forecast.today` — one line as WeatherKit's summary gives it ("Rain after 6 PM, high 61°"),
  plus `forecast.today.high_f`, `low_f`, `rain_chance_percent`, `rain_in`;
- `forecast.tonight`, `forecast.tomorrow` — the same shape;
- `forecast.next_rain` — "this evening around 6" / "not this week", human-grained;
- `sun.rise`, `sun.set` — clock times are right here: they *are* the fact;
- `weather.alert` — an active NWS alert's headline, valid until it expires; a happening
  (`weather.alert_issued`) when one appears, so it is a candidate for a house remark under the
  usual rules (quiet hours apply; wind advisories at 3 AM wait for morning).

**Glossary seeds:** each predicate's meaning, in the plain words the world's own catalogue uses.

**Moment:** "Beaky, do I need a coat?" answered with tomorrow's high and the rain window; and one
morning, unprompted, "Wind advisory this afternoon, April — the orchard's going to be loud."

## Step 3 — The address book: people become real

**Source:** the Contacts framework (TCC: Contacts). Deterministic; no model.

**The whole card is stored.** April: "address book entries, too" — it is fine to keep them in the
world. Facts on `person:<slug>`, each with `derived_from` the contact's identifier and no
`valid_to` (until the card changes; a changed card re-casts, a removed one retracts):
- `contact.phone` (all numbers, labelled: `{"mobile": "…", "home": "…"}`), `contact.email`,
  `contact.address` (labelled, as strings), `contact.organization`, `contact.job_title`;
- `contact.birthday`, `contact.anniversary`, and the other dates on the card;
- `contact.nickname`, `contact.pronouns` (where the card carries them — and the world's
  `identity.pronouns` gets them too, which the personas already read);
- `person.relationship` — from the card's related names ("sister", "contractor") or April's own
  label in the Bridge's map; and `contact.note`, the card's notes field, if April turns it on
  per contact (notes are where people write things they would not want read aloud).

**Audience, per kind, April's toggle.** Defaults: `contact.phone`, `contact.email`,
`contact.address`, `contact.note` are `world` — stored, on the entity page, usable by rules, never
in a prompt; `contact.birthday`, `contact.organization`, `contact.nickname`, `person.relationship`
are `minds`. Any of it can be flipped in Meanings. "Beaky, what's Jesse's number?" is answered by
the Viewer, not the bird, unless April decides otherwise.

**Entity resolution — April decides, once.** A contact becomes a world entity only when April maps
it, in the Bridge's window: "Jesse Alvarez → `person:jesse`". Contacts whose name already matches
a `person:*` the world knows (Jesse, Polly) are offered first, pre-filled; unmapped contacts are
never cast. The map lives on the Mac and is the same map Messages and the calendar use in later
steps. This is the single rule that keeps four hundred contacts from becoming four hundred
half-known people.

**Why before the calendar:** it makes `person:jesse` a hub with something on it before any calendar
or text mentions him, it is the cheapest source to get right, and the audience mechanism gets
exercised on the facts that most need it.

**Moment:** "Beaky, who is Jesse?" → "Your contractor, April" — from a `person.relationship` fact
the Bridge cast, not one April typed. "When is Polly's birthday?" answered. The Viewer's entity
page for Jesse shows phone, email, and address in grey (world-only) and the rest in the normal
colour (minds).

## Step 4 — Calendar: visitors and errands

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

## Step 5 — Mail: orders, deliveries, appointments

**Source:** a MailKit extension or a Mail rule that hands messages to the Bridge (TCC: Mail via
the extension; the Bridge never reads the mailbox directly). Cheap deterministic classification
first — sender domain, subject patterns, list-unsubscribe headers — into `order`, `shipping`,
`appointment`, `receipt`, `newsletter/irrelevant`. Only the first four reach the model; the rest
are `classified_irrelevant` and forgotten. The merchant and carrier lists are April's, in the
Bridge's window, seeded from what the classifier finds in the last month.

**Extraction (on-device):** Foundation Models guided generation into small typed results, each
field marked present-in-source or inferred; only present-in-source fields become facts:
- `Order` — merchant, order number, items *as the mail names them*, total, placed-on;
- `Shipment` — carrier, tracking number, order number if given, status (`shipped`, `out for
  delivery`, `delivered`), window;
- `Appointment` — who/what, when, where (dentist confirmations, service visits, reservations);
- `Receipt` — merchant, what, amount, when (so "did I pay the ferry reservation?" has an answer).
Model unavailable → source `degraded`, items wait, nothing is sent elsewhere.

**Orders are entities in the world.** April: "I think we should use order numbers in the database
and it's okay to store those." `order:<merchant>-<number>` with `order.merchant`, `order.number`,
`order.items` (the list, as strings), `order.placed`, `order.total`, `order.status`
(`placed` → `shipped` → `out_for_delivery` → `delivered`), `order.tracking`, `order.expected`,
and a link `order.for = person:april`. All `minds`. `valid_to` none while open; the Bridge retracts
nothing — an order delivered in May is still an order in December, and "did I ever order a
Prusa nozzle?" is a fair question. A shipment with an order number updates that order; one
without becomes `order:<carrier>-<tracking>` until a later mail joins it.

**The founding fact** is a world rule over orders, not a special case: an `order:*` with
`order.status = out_for_delivery` → `house:aprils-nest · delivery.expected = "<items> (<carrier>),
today"`, valid until midnight; `delivered` → `delivery.arrived`, valid 6 h. The truck in the
driveway meets it, and Sol puts them together.

**Appointments** are `event:*` entities exactly like the calendar's (step 4), with
`calendar.source = mail`, so the same visitor rule and the same timers apply; a service visit at
the house is a visitor.

**Asking about it:** "Did I order a servo?" is a solo question to Beaky. The world's mention
resolver (`WorldMentions`) grows a second lookup: words in the question matched against
`order.items` across current orders, so the matching orders join the subjects of the percept.
No tool call; the facts arrive with the question, as everything does.

**Moment:** "April, the robot parts are here!" — unscripted, from a mail she never showed
anyone. And "Did I order a servo?" — "Four, from Adafruit, on the 9th; they were out for delivery
this morning."

## Step 6 — Messages: what people tell April

**Source:** the Messages database (`chat.db`; TCC: Full Disk Access) read-only, or the supported
automation path if macOS 27 offers one — decided when we get here. Only conversations April
allowlists in the Bridge (by mapped person) are read at all; group chats off by default. April's
own outgoing messages are read only to resolve a reply ("yes, 6 works") — never cast.

**Extraction (on-device):** from a message by a mapped person, present-in-source fields only:
- `SocialCommitment` — who, what, when, where: "running late, there by 6" →
  `person:polly · visitor.expected = "tonight around 6"` (valid until 9 PM);
- `Request` — someone asked April for something: "can you grab milk?" →
  `person:polly · asked_april = "to grab milk"` (valid a day); Beaky may remind, or not;
- `News` — something a person said about themselves that April would want the birds to know:
  "got the job!" → `person:polly · news = "got the job (said Tuesday)"` (valid a week; the
  nightly memory decides whether it is worth keeping longer, as with anything else);
- `DeliveryNote` — the ones carriers send by text ("your package was left at the front door") →
  the same `delivery.arrived` rule as mail.
No sentiment, no summaries of conversations, no verbatim text. The value is the fact, in the
Bridge's words; the message id is the provenance.

**Moment:** the door unlocks at 6:04; "That'll be Polly, April — she said around six." And the
next morning, unprompted: "Polly starts the new job today, doesn't she?"

## What the Viewer shows, per step

| Step | Viewer |
|---|---|
| 1 | Entity page; audience in Meanings; the Bridge as an entity with source health; `bridge:*` on the timeline |
| 2 | `forecast.*` and `sun.*` on `place:outside`; a `weather.alert_issued` happening on the timeline |
| 3 | People with the whole card: phone/email/address/notes greyed (world-only); birthday, organization, relationship in the normal colour |
| 4 | `event:*` entities; `visitor.expected` with `derived_from` the calendar event; the reducer's decision on the timeline |
| 5 | `order:*` entities with status and items; `delivery.expected` on the house; the scene where the truck met it |
| 6 | `visitor.expected` / `asked_april` / `news` from a text, showing only the person and the source kind |

## What the Bridge shows, in its own window

Sources and their health; permissions with the fix for each; April's contact→entity map; calendars
allowed; the merchant/carrier list; the Messages allowlist; the outbox; a redacted inspector of the
last N *facts* sent (never the sources); a "cast a test fact" button; model availability. Vim-free.

## Versions

- Step 1: World `0.25.0`, Viewer `0.7.0`, Bridge `0.1.0`.
- Step 2: Bridge `0.2.0`; glossary seeds; `weather.alert_issued` as a storyworthy happening (World).
- Step 3: Bridge `0.3.0`; glossary seeds only.
- Step 4: World `0.26.0` (visitor reducer, calendar timers), Bridge `0.4.0`.
- Step 5: World `0.27.0` (delivery rule over orders, order mentions), Bridge `0.5.0`. Tag the day
  the sentence is said.
- Step 6: Bridge `0.6.0`.

Each step: docs (this plan's status line, `beakys-world.md` §0, a `docs/information-bridge-manual.md`
started in step 1), tests (a deterministic fake distiller; the world's reducers under the black-box
suite), and the Viewer surface, in the same commit.

## Open questions for April

0. **WeatherKit needs the house's coordinates and an entitlement** on the signed app — the same
   developer account as the Console; fine?
1. **Which Mac, exactly, and who is logged in?** The plan says the M1 MacBook Pro, lid closed, April
   logged in. Does it sleep? (Amphetamine / `caffeinate` / power settings are part of step 1.)
2. **Contact mapping:** the plan pre-fills matches to people the world already knows and asks
   about everyone else. Should a whole group ("Family", "Contractors") map at once?
3. **The calendar horizon** (7 days?) and which calendars. Does "April's dentist" belong in Beaky's
   mouth at all, or only visitors-to-the-house?
4. **Merchants and carriers list** for step 5 — seed from the last month of mail, then yours to edit?
   And how far back should the first run read: a month of orders, a year?
5. **Messages access path:** `chat.db` under Full Disk Access is the known-working way; is that
   acceptable on this Mac, or wait for a sanctioned API?
6. **Audience granularity:** two levels (`minds` / `world`) or three (add `lead` — only Beaky)?
   Two is enough for the plan; three is a small change later.
7. **Does the Bridge get a bird?** It is an entity (`thing:information-bridge`) with health facts.
   It does not speak. Unless you want it to.
