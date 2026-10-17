# Orders become history (#234)

April, 2026-10-15: "We should have Beaky recommend to remove deliveries that are several days
old." Dozens of `order:*` facts from the Bridge were still current a month later, with no
`valid_to`; a `shipped` from June had the birds expecting a DJI mic "tomorrow" on 2026-09-14.

## Decided (2026-10-16)

- A **delivered** order stays current for **3 days** after the mail said so.
- A **shipped or placed** order with no further word stays current for **14 days**.
- An old order is **kept as history**: its facts end, and stay on the record.

## The rule (World 0.56.0)

`DeliveryRule.settle`, beside the delivery sweep, every minute. The age is counted from the
mail's own date, `order.updated_at`; the backfill date is the fallback. An order past its time
gets one `order.settled` event from `world:orders` (payload: status, last heard, reason), keyed
by the status fact it settles. `OrderReducer` ends every reported `order.*` fact on it with a
null ending. A later word from the mail is a new status, and settles in its own time. At most
100 orders per pass, so the first sweep of the backlog is gentle.

## Beaky's part (agent 2.96.0)

The rule only sees the mail's orders. The librarian's instructions now say that a delivery a
bird kept (`thing:speaker · order.status = delivered`, by mind:beaky on Oct 8) is news only for
a few days, and to recommend retiring it once it arrived or was due more than three days ago.
April reviews and applies these in the Nightly panel, as with any filing.
