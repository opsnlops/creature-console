# A visit that ends, ends (#228)

## What happened

On 2026-10-14 the propane supplier came at 8:21 AM to refill the big tank. The four birds kept
it as `thing:propane-supplier · visitor.expected` (twice) and `visitor.purpose` (twice), all
until midnight. April said at 1:34 PM and 1:50 PM that they were long gone; the birds learned
only a note on the carport, and nothing ended the supplier's facts. All afternoon the house's
stage note for every camera scene said "a visitor is expected - today, refilling the big
tank -", and the birds offered the tank visitor for every car, the cleaner included.

## Changes

1. **World: ending a visitor ends the visit.** A `facts.given` that ends `visitor.expected`
   (a `null`), or says the subject's `presence.state` is `away`, retracts every *reported*
   `visitor.*` fact on that subject (`FactRetraction`, as an observed arrival does for
   `presence.*`). One "they're gone" clears what the visit was for too.
2. **World: the stage note says when.** `Household.situation` words a visitor as
   "…, expected since 8:22 AM", so a mind can tell a visit said hours ago from one said now.
   April: "Try to remember timestamps and how long it takes for a thing to happen."
3. **Agent: the learning contract.** Someone already here is kept with a span for how long the
   visit should take (`2h`), never `today`. When April says someone has left, the bird ends
   that visitor's `visitor.expected` with `none`, on them - a note on the place where a camera
   saw something does not end the visit.
4. **Tests** with today's shape: the four facts, then an ending, then nothing about the
   visit in force; the stage note's wording; the contract's words.

Versions: world 0.47.3, agent 2.87.3 (fixes).
