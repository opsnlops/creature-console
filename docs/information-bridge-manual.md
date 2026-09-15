# Information Bridge — Manual

What April's Mac knows, the world learns. The Bridge is a macOS app that reads private things
*here* — on this Mac, under this Mac's permissions — and sends only distilled facts to Creature
World. It is a source of facts for Beaky, never a bird; it does not speak. The plan it follows is
[`information-bridge-plan.md`](information-bridge-plan.md).

## Where it runs

April's M1 MacBook Pro (48 GB), logged in as April, kept from sleeping. Bundle
`io.opsnlops.Information-Bridge`, in the Creature Console Xcode project as the **Information
Bridge** scheme, macOS only. Not sandboxed (Messages' `chat.db` and Full Disk Access need that);
hardened runtime on. Build and run it from Xcode; it lives in the menu bar and keeps working with
its window closed.

## Mail (`0.6.0`, plan step 5)

Settings → **Mail** → turn it on, add each IMAP account (host, user name, password — the
password goes to the Creature family's shared Keychain, synchronizable, so it is there on the
next Mac too), and list the carriers and merchants whose mail may be read (one domain per line;
the defaults are the usual suspects). No Mail.app in the loop: the Bridge reads each account
itself. The first read of a mailbox goes back 120 days; every read after — every five minutes,
or **Read now** — asks only for what is newer than the last UID seen, remembered per mailbox on
this Mac. Every mailbox is read but Sent, Drafts, Trash, and Junk (April's rules file mail into
folders such as Amazon and Deliveries).

Each message is classified cheaply by sender and subject (order, shipping, appointment, receipt,
or irrelevant — the last is forgotten at once), read for the parts with a shape (order and
tracking numbers, the status in the subject, items named on the subject line), and then read by
**Apple Intelligence on this Mac** into the same shape for the rest — item names, totals, the
carrier's window. When the model is not available the Mail row says so and the shaped parts
stand alone. Mails about one order fold into one `order:<merchant>-<number>` entity — a
carrier's tracking number joins the merchant's order — with `order.merchant`, `order.number`,
`order.items`, `order.status`, `order.carrier`, `order.tracking` (world-only), `order.total`,
`order.placed`, `order.expected` (the carrier's window as a day — "arriving tomorrow" on a June 7
mail is `June 8, 2026`, and the window is dropped once the order is delivered), `order.last_heard`
(the day the mail last spoke of it, so a bird knows a shipped order from June is old news, not
news), `order.updated_at` (world-only; the same, as a timestamp for the world's rules),
`order.for = person:april`; kept for good. A tracking number the model offers is taken only if it
looks like one (letters and digits, at least six digits). Every fact line a mind reads is stamped
with when the *world* learned it, which for a re-read is minutes ago — so the order meanings say
outright that `order.status` and `order.expected` are as of `order.last_heard`, and that the mail
rarely says when a package actually came. Item names are tidied (bidi marks, ellipses, Amazon's
"and 1 more item", the model's "Shipment"/"Item" placeholders dropped); totals read "$21.69".
When the readers improve, the Bridge's *reading version* is bumped and the mail is read again,
the order book rebuilt from scratch, and orders that no longer exist taken back. The Sources card
lists the orders it knows and, on the Mac, `mail-readings.log` says what each message became
(date, kind, sender, subject — never a body). The world's own rule turns *out for delivery* into
`delivery.expected` on the house — "April, the robot parts are here!" is the world's, not the
Bridge's.

## Calendar (`0.4.0`, plan step 4)

Settings → **Calendar** → turn it on; macOS asks once for full access to Calendars. The Sources
card then lists every calendar with a checkbox — all read until you untick one. Everything ahead
and the last 90 days becomes an `event:<id>-<day>` entity (one per occurrence of a repeating
event) with `calendar.title`, `calendar.when` ("Thursday, September 17 at 2:00 PM"),
`calendar.location`, `calendar.calendar`, `calendar.all_day`, world-only `calendar.starts_at` /
`calendar.ends_at` for the world's rules, and `calendar.with = person:jesse` when an attendee's
email or name matches a mapped card, or a mapped person's first name is in the title. **Your own
word wins:** a line `Beaky: person:jesse` in the event's notes says who it is with whatever the
guess was, and `Beaky: nobody` says there is no one — edit the event in Calendar on any device.
The rest of the notes never leave the Mac. Each event's facts hold until 90 days after it ends, so "when was Jesse last here?"
has an answer. Re-read hourly; a moved event re-casts, a cancelled one is taken back. The world's
own rule turns an event at the house with a person into `visitor.expected` — that is the world's,
not the Bridge's.

## Address Book (`0.3.0`, plan step 3; the card keeps its own word since `0.7.0`)

Settings → **Address Book** → turn it on; macOS asks once whether the Bridge may read Contacts.
Then **People…** in the Sources card opens the map: every card in the address book, a field for
the person it is in the world (`person:jesse`), and a field for what they are to April ("my
contractor") which becomes `person.relationship` in her words. **The map lives on the card
itself** — a URL labeled **Beaky** reading `person:jesse; my contractor` — so it syncs with the
address book, can be edited in Contacts on any device (change the value, or delete the field to
unmap), and goes with the Bridge when it moves to another Mac; the People window is just a
convenient editor for that field, and re-reads the cards after every change. (The Notes field
would have been nicer, but Apple gates it behind an entitlement the Bridge does not have.) A
`contacts-map.json` from before `0.7.0` is written onto the cards once, then set aside as
`contacts-map.moved`. **A card becomes a person in the world only when it is mapped**; the rest
of the address book stays on the Mac. Where the world already knows a person by that first name
and no other card is mapped to them, a **Use person:jesse** button pre-fills it.

A mapped card's whole content is cast on the person, with no expiry: `contact.name`,
`contact.nickname`, `contact.phone`, `contact.email`, `contact.address` (each by the card's own
labels), `contact.organization`, `contact.job_title`, `contact.birthday` ("March 4"), and
`person.relationship` (April's word, else the card's related names read the other way round).
The glossary is seeded with **phone, email, and address as world-only** — stored, on the entity
page, never in a prompt — and the rest for the minds; flip any of them in the Viewer's Meanings.
The book is re-read hourly; a changed card re-casts what changed, a card unmapped (or gone from
the book) has every fact taken back, and a card mapped to someone else moves.

## Weather (`0.2.0`, plan step 2)

Settings → **Weather**: turn it on. The house is wherever this Mac is: macOS asks once whether
the Bridge may know its location (System Settings → Privacy & Security → Location Services if
you said no), the Bridge remembers the fix so a restart does not wait for one, and re-checks on
each start in case the Mac moved. Turn off "The house is wherever this Mac is" to type
coordinates instead. The Bridge asks WeatherKit once an hour — the daily forecast, the next two days by the
hour, any alerts — and casts facts on `place:outside` (the Place field, if the house's outside is
called something else), each holding until the end of the period it describes, and only when its
value changes:

- `forecast.today` — "Partly cloudy, high 61°, low 52°, 30% chance of rain (about a quarter
  inch)", with `forecast.today.high_f`, `.low_f`, `.rain_chance_percent`, `.rain_in` beside it;
- `forecast.tonight` — the evening hours summed up; `forecast.tomorrow` and its numbers;
- `forecast.next_rain` — "this evening around 6 PM, 70% chance", or "not in the next two days";
  holds only until the rain comes;
- `sun.rise`, `sun.set` — clock times, which here are the fact;
- `weather.alert` — an alert in force, until it expires.

The meanings are seeded into the world's glossary when a source starts; a meaning the Bridge
itself wrote last is brought up to date when its words change (since `0.7.1`), and a Wizard's
rewording is never overwritten. **Read now** in the Sources card reads the sky without waiting for the hour. The
Apple Weather mark and the data-sources link are shown in the Sources card, as Apple's terms
require. A failed reading shows the source as degraded with the reason; the Bridge tries again on
the hour.

## What it does (`0.1.0`, plan step 1)

- **Talks to one world.** Settings (⌘,) hold the world's address (default
  `server.prod.chirpchirp.dev:443`, TLS), the proxy if any, and the house it speaks for
  (`house:aprils-nest`). The window's title bar shows the effective `/world/v1`.
- **A durable outbox.** Every fact goes to `~/Library/Application Support/Information
  Bridge/outbox.json` first, then to the world in order, at least once, with backoff from two
  seconds to five minutes — a hundred at a time through `events:batch` when there is a backlog
  (`0.5.1`), so a first read of a calendar clears in seconds. A world that is down, a laptop asleep, a proxy that blinks: the fact
  waits and goes when it can. The world deduplicates on the source's item id, so a retry that
  already landed is a no-op. The window shows what is waiting, what was delivered, the last error,
  and when it will try again.
- **Its own heartbeat.** `thing:information-bridge · bridge.online = "Information Bridge 0.1.0 on
  <mac>"`, valid an hour, re-cast every thirty minutes: a Bridge that stops is a fact that
  expires. The Viewer shows the Bridge as an entity.
- **Cast a test fact** (toolbar, or the menu bar): `house:aprils-nest · bridge.hello`, valid a
  minute, through the real outbox. Watch it arrive on the Viewer's timeline as `bridge:app`,
  and Forget it if you like.
- **Sources**, all off — Weather, Address Book, Calendar, Mail, Messages — each with the step of
  the plan that brings it to life. Nothing is read until then.
- **Sent to the world:** the last fifty facts, as `subject · predicate = value`. Never the
  sources.

## Every fact the Bridge sends

A `facts.given` event: source `bridge:<source>` of kind `bridge`, `source_event_id` the item's own
stable id, epistemic `reported`, and usually `valid_for_seconds` — a delivery is today's, a visitor
is Thursday's. April can Forget any of it in the Viewer.

## Provisioning

Automatic signing on the Creature developer team. The App ID has **WeatherKit** ticked under App
Services on developer.apple.com (April registered it by hand on 2026-09-14) and the entitlement is
in `Information_Bridge.entitlements`. TCC
permissions — Contacts, Calendars, Full Disk Access — are asked for by the step that needs them.
