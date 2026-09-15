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

## What it does today (`0.1.0`, plan step 1)

- **Talks to one world.** Settings (⌘,) hold the world's address (default
  `server.prod.chirpchirp.dev:443`, TLS), the proxy if any, and the house it speaks for
  (`house:aprils-nest`). The window's title bar shows the effective `/world/v1`.
- **A durable outbox.** Every fact goes to `~/Library/Application Support/Information
  Bridge/outbox.json` first, then to the world in order, at least once, with backoff from two
  seconds to five minutes. A world that is down, a laptop asleep, a proxy that blinks: the fact
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

Automatic signing on the Creature developer team. The App ID needs **WeatherKit** ticked under App
Services on developer.apple.com before step 2 (it takes up to half an hour to provision). TCC
permissions — Contacts, Calendars, Full Disk Access — are asked for by the step that needs them.
