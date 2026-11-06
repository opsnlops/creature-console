# Flock Communicator history (#282) — built: World 0.70.0, gateway 0.2.0, Flock Communicator 0.6.0

April, 2026-11-05: "Flock Communicator grabs all conversation back to the beginning of time.
That's only going to grow as time goes on."

Measured 2026-11-06: 10,487 items, 4.9 MB, 105 pages of 100, 7.9 s, growing about 200 items a
day. Every launch paid that, plus one SwiftData fetch per item, and every live update then decoded
the whole cache.

## What it should feel like

- A launch shows the cached conversation at once and fetches only what it missed.
- A new device, or a cleared cache, fetches one page and is ready.
- Scrolling up keeps going, all the way to the first message. There is no cap.
- A live update costs a window of a few hundred rows, however long the history gets.

## The trap in the obvious fix

The obvious fix is to resume from the newest cached item. That item can be a turn this device has
just sent, sitting past turns it never fetched: the outbox flushes, the history fetch fails, and
the next sync starts after the sent turn and skips the gap for good. Today's full download at every
launch is what quietly repairs that.

So the sync position must be its own durable fact, not something inferred from the cache.

## The design

### World and gateway: read backward

`GET .../conversations/{id}/items` keeps `after_item_id` for everyone who reads forward, and gains
newest-first paging:

| Query | Page |
| --- | --- |
| `order=newest` | the newest `limit` items |
| `before_item_id=X` | the `limit` items just older than X |
| neither | forward, as today, with `after_item_id` if given |

- Items in a page stay oldest first, whichever way it was found. `next_item_id` is the page's
  oldest item, and `has_more` says whether anything older exists.
- `after_item_id` with either backward parameter is a 400. So is an unknown `order`.
- A `before_item_id` that isn't in this conversation is a 400, like `after_item_id`.
- Both servers parse this with one `ConversationPageRequest` in WorldCore.

The sort walks the existing `conversation_order` index in reverse, so no new index.

### App: what the cache promises

`ConversationSyncStateModel`, one row per server:

- `newestItemID`: forward sync has everything up to here.
- `oldestItemID`: the cache reaches back to here without a gap.
- `reachedBeginning`: nothing older exists.

The promise: **the cache is one unbroken run from `oldestItemID` to `newestItemID`, plus any turns
this device has sent since.** Each write keeps it, in one save:

- **Start** (no state row): fetch the newest page, delete every cached row outside it, write the page
  and the state. This is also the upgrade: a cache from an older build has no state row, and
  nothing proves it has no gaps. It stays readable until a start succeeds, and older rows come back
  by scrolling. The delete is what makes the promise true.
- **Catch up**: page forward from `newestItemID`, advancing it with each page, so an interrupted
  catch-up resumes where it stopped.
- **Backfill**: fetch the page before `oldestItemID`, moving it down. The write is dropped if the
  state has moved on since the request went out.

The cursor is read *before* the outbox flushes, as it is today. A flushed turn lands in the cache
without moving `newestItemID`, and catch-up delivers it again, harmlessly, because writes are
idempotent by item ID. That closes the trap.

A rejected cursor (a 400, or a page that doesn't advance) means the canonical history was replaced,
so the app starts over. A network failure doesn't: it keeps its place and tries again next time.

Clearing the cache also deletes the state row, so the next sync is a start. The outbox stays.

### App: what the screen reads

The repository reads a window, never the whole cache:

- By default, the newest 200 rows. Rows slide off the top as new ones arrive.
- Once someone scrolls up, everything from a start date onward. It's a date rather than a row so
  that the rows on screen stay put, and rows sharing that date all come along.
- Unsent turns always show.

`hasOlder` is true while there are cached rows above the window or the beginning hasn't been
reached. Above the first row, the view shows a loading row while `hasOlder`, and the welcome header
once the beginning is reached. Loading older moves the window up a page, fetching first if the
cache has less than a page left. If the fetch fails but some cached rows remain, those show. If
nothing does, the row offers a retry rather than an alert.

Each window carries a revision taken when its read starts, and the store ignores any window older
than the one on screen. Otherwise a refresh already in flight could undo a scroll back.

`load()` shows the cache before touching the network, and the spinner only appears if there is
nothing to show.

### The gateway

The gateway used to answer every World failure with a 503, so a rejected cursor looked like an
outage and the app would never have started over. It now passes a World 400 through as a 400.

### Batching

Cache writes fetch a page's existing rows in one query, rather than one per item, and leave
unchanged rows alone.

## Deploy order

World and gateway first, then the app. An older server ignores `order=newest` and answers with the
oldest page. That doesn't corrupt anything, because catch-up then reads forward to the end, but it
is the full download again.

## Not in this change

- A window someone has scrolled back stays expanded until the app relaunches.
- A new turn still scrolls to the end even if you are reading old history. That was already true.
- The World Viewer reads forward as it always has, so it has nothing new to show.
