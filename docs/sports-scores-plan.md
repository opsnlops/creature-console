# Sports scores in the World (#269) — built: house 0.6.0, World 0.65.0

On 2026-10-29 April asked the flock a question that turned on whether the Seahawks had lost in
the last 24 hours. All four birds reasoned it through correctly, time zones and all, and then said
they did not know whether the Seahawks had lost. Nothing in the World tells them.

April chose the source: Home Assistant's **Team Tracker** integration
([vasqued2/ha-teamtracker](https://github.com/vasqued2/ha-teamtracker), from HACS), not a path
from the World to the internet. The World stays offline; Home Assistant polls ESPN; creature-house
already streams Home Assistant into the World. Her sensor is `sensor.seattle_seahawks`.

## Team Tracker, as it really is

From its source (`set_values.py`, `parse_espn.py`), not only its README:

- **State** is ESPN's, upper-cased: `PRE`, `IN`, `POST`, plus `BYE` and `NOT_FOUND`.
- **`date`** is the kickoff, as ESPN writes it: `2026-11-03T01:15Z`, with no seconds.
- **`team_score` / `opponent_score`** are **strings** (`"20"`; `"2(4)"` after a shootout).
- **`team_winner`** is a bool in `POST`, `null` before. Some APIs send `"true"`, which Team
  Tracker turns into a bool.
- **`team_long_name`, `opponent_long_name`, `team_homeaway`** (`home` / `away`).
- **Which game it shows:** the last one, `POST`, until the next is within **12 hours**; then that
  one, `PRE`. Most of the week the sensor is last game's final, and the next game is known only
  on game day.
- **Polling:** every 10 minutes, and every 5 seconds during a game and for about 20 minutes
  before it. So the moment the sensor goes from `IN` to `POST` is the final whistle, to within
  seconds. ESPN's schedule has only the kickoff.

## The design (house 0.6.0, World 0.65.0)

1. **A `game` mapping kind in creature-house.**
   `{ "entity_id": "sensor.seattle_seahawks", "subject_id": "team:seahawks", "kind": "game" }`.
   `TeamTracker.swift` reads a state into a game: kickoff, team, opponent, and home or away.
   Once it is under way it also reads the scores, the clock and the last play, and in `POST`
   the result. A game is known by its kickoff.
2. **Three events, each one per game.**
   - `game.scheduled`: `PRE` for a game the World has not heard of yet.
   - `game.started`: `IN`.
   - `game.final`: `POST`, with both scores and `won` / `lost` / `tied`. It also carries
     `ended_at` when the house saw the game go from `IN` to `POST` itself.

   Each is keyed by the game (`game:<kickoff>:final`), not by Home Assistant's context. The first
   one the World hears is the one it keeps. A live final, with its `ended_at`, is never replaced by
   a restart's snapshot of the same game, which can't know when it ended. And a snapshot after a
   deploy still fills the blank.

   **Scores (added the same evening).** April: "let's send a scene consider on when one of the
   teams in the game scores." While a game is `IN`, a score going up is `game.scored`, with
   `scored_by`, both scores, the clock and the last play. A correction that only takes points
   away (a touchdown overturned on review) is `game.score_corrected`; April: "I look forward to
   Mango's commentary on when they have to correct the score." A score is keyed by Home
   Assistant's context, not by the score, so a touchdown overturned and scored again counts
   twice.

   Odds, the clock and records changing under the same state are not news. An unavailable
   sensor (Home Assistant restarting) is not news either, and the announcer remembers the last
   state the World heard, so coming back as the same `POST` is not a second final.
3. **`GameReducer` in the World keeps three facts on the team.**
   - `game.next`: from `game.scheduled`.
   - `game.playing`: from `game.started`, then each score or correction, with both scores and
     the clock then. It ends `game.next`.
   - `game.last`: from `game.final`. It ends `game.playing` and `game.next`.

   The values carry the house's fields plus times in words, in the World's time zone (the
   memory job's): "Monday, November 2 at 5:15 PM". Minds read the words; `kickoff` and
   `ended_at` stay as timestamps for the record.
4. **The glossary** gets a sentence for each, so the minds know what they are.
5. **The minds need nothing new.** When April asks, a bird looks up `team:seahawks` with the
   World tools it already has (`search_world` finds "Seahawks" in the id and the values). April:
   "I don't want to put the sports info in the message envelope." The game facts are on no
   page, even when the Seahawks are named: a page brings in named people and orders, never a
   team.
6. **The house asks about each score.** The packaged `world.json` has two `consider_on` lines,
   `game.scored` and `game.score_corrected`, each with a three-minute cooldown: a touchdown
   and its extra point are one remark. The scene opens in the lead's room, because a team is
   in no room. The trigger says who scored on whom, the score, the clock and the play
   ("Chicago Bears just scored against Seattle Seahawks, the team April follows: …"). Quiet
   hours, and never interrupting a conversation already going, hold as they do for every
   house question. To stop it, take either line out of `world.json`.
7. **Viewer:** the team's facts are in Entities, and the `game.*` events are on the timeline.
   Nothing new is needed to see them.

## Fixed after the first game (house 0.6.1, World 0.66.1, #271)

The Bears scored twice on 11-02 and nobody was asked. The touchdown arrived as April started a
conversation, and was rightly held back. It spent the cooldown anyway, so the extra point
found it spent. The World now starts a cooldown only when its scene opens. Both scores also
carried the kickoff's time: Home Assistant's `last_changed` moves only with the state, so a
score now happens at `last_updated`.

Still open: a score held back by a conversation is not asked about once it ends; the next
score is.

## Possession, and a quiet hour (house 0.7.0, World 0.67.0, agent 2.107.0, #272)

During the same game April asked "Are we getting possession changes, too?", then "Let's do
both 1 and 2. I'll change it if it's too much." The pieces:

- **The house** reports `game.possession` whenever the ball changes hands. It reads Team
  Tracker's `possession` and names the side by `team_id` / `opponent_id`, with `down_distance`.
- **`GameReducer`** keeps `possession` and `down_distance` in `game.playing`.
- **The packaged `world.json`** asks the lead about each change of hands, 60 s apart. The lead
  may stay quiet for a punt.

Then: "Let's give me a kill switch like we do for the cameras. 'Beaky, ignore the game for the
next hour'". A bird keeps `house.games_quiet` on the house, with an expiry, and ends it with
`none`. While it holds, no game event opens a scene, and the game is still recorded.

Live, the same night (house 0.7.1, World 0.67.1): after the Seahawks' field goal the birds
heard "Seattle Seahawks now has the ball". ESPN names nobody on a scoring play, and the house
remembered that blank, so the scorers' own kickoff read as a change of hands. The last known
side now outlives a blank. The trigger also reads "The ball just went to …", which says it is
a change.

## First downs, flags and reviews (house 0.8.0, World 0.71.0, #287)

Watching Seahawks–Cardinals on 2026-11-08, April asked whether the birds could know when a
challenge flag is thrown, then about fouls, then: "I'm really enjoying watching the game with
the birds and I want them to chat more", and "Let's also add a scene opener on every first
down. I might have you tone it down, but let's see if that annoys me."

What ESPN gives, through Team Tracker's `last_play`:

- **Fouls** are written up with the play, seconds after it:
  `PENALTY on CHI-J.Lynch, Roughing the Passer, 15 yards, enforced at SEA 24 - No Play.`
  Declined flags say `declined`; offsetting ones say so.
- **Reviews** are written up only once decided: `SEATTLE challenged the pass completion
  ruling, and the play was REVERSED.`, or `The Replay Official reviewed …, and the play was
  Upheld. The ruling on the field stands.` The flag itself never appears.
- **First downs** are in `down_distance_text`, which the house already reads.

The pieces:

1. **The house** reports, under way and after a score and the ball changing hands:
   - `game.reviewed`: `challenged_by` (as ESPN writes it; absent for the booth) and `outcome`
     (`reversed`, `upheld`, `stands`)
   - `game.penalty`: `penalty_on` (the side's name when ESPN's short name matches `team_abbr`
     / `opponent_abbr`, otherwise as written: the Cardinals are `ARI` in the sensor and `ARZ` in
     the plays), `foul`, `yards`. Declined and offsetting flags are not news.
   - `game.first_down`: the down back to `1st` for the side that already had the ball, at a new
     spot.

   One play is one event, the biggest of: score, possession, review, flag, first down. A
   flag's automatic first down is the flag. Each needs a write-up the World has not heard, and
   both the write-up and the down are compared with what the World last heard, so a play whose
   write-up and down arrive in separate looks is still one first down. Reading ESPN's fixed
   wording is parsing; which fouls are worth a word is the lead's to judge.
2. **`GameReducer`** treats all three like `game.possession`: `game.playing` keeps the score,
   the ball, the down and the clock as of the last play told.
3. **Stage notes:** "Kansas City Chiefs just picked up a first down in the game between …",
   "A flag in the game between …: Defensive Pass Interference on Seattle Seahawks, 16 yards.
   The score: …", "A replay review just finished in the game between … - SEATTLE challenged,
   and the call was reversed. The score: …". Each ends with the clock, the down and the play.
4. **The packaged `world.json`:** `game.reviewed` and `game.penalty` 60 s apart,
   `game.first_down` with no cooldown, for now. To tone it down, raise a cooldown or take a
   line out. `house.games_quiet` silences all three.

**Every play** (house 0.9.0, World 0.73.0). Live, every one of these opened a scene and the
birds talked through all of them, but at one every 3–4 minutes April was "wishing they said
more", then "Let's try every play and see how annoying it is." Any other snap that moves the
down is now `game.play`, with the new `down_distance` and the `last_play`, and the packaged
`world.json` asks the lead about each with no cooldown. It paces itself: a house question
never interrupts an open scene, so plays during a scene go by and the next one after it gets a
remark. A write-up that moves no down, such as an official timeout, is not a play. The next
lever, if it is still thin, is longer game scenes than the house's three turns.

The same build asks for feelings. April: "Can you ask them to be really emotional, too? It's
fun when they get super happy on good plays." Every game stage note ends: "You are watching
with April as fans of Seattle Seahawks: feel it out loud, each in your own way - overjoyed at a
good play for Seattle Seahawks, crushed or indignant at a bad one."

**A field goal missed, and a down misread** (house 0.9.1, World 0.73.1). Late in the third,
ESPN moved the score to 17–3 before writing up the field goal, so the stage note carried the
8-yard run before it again; Beaky passed, "already celebrated this play". And "(4:37 - 3rd;
4th & 7 at ARI 26)" after a 3rd-and-15 run read to Caroll and Mango as a fourth down converted.
Now a write-up the World already heard is left out of the next event, a score carries
`points` ("just scored 3 points against …"), and the down reads "next: 4th & 7 at ARI 26".

**The game so far** (World 0.74.0). April: "Would we get a better show performance if we
modeled the game in the server's memory?" Not faster (the time is the minds and the TV
delay), but better told. The World already has every play of the game in its record, so for a
game's stage note the scene opener reads the team's events since kickoff and `GameStory` adds
what a person on the couch knows: "This play started from 3rd & 15 at ARI 34. The plays
before it: …. Seattle Seahawks' drive: 6 plays so far, since getting the ball at SEA 16 (11:25 -
3rd)." Read from the record, it survives a restart, and nothing new is stored.

**The scoreboard** (house 0.10.0, World 0.75.0). April: "What I'm picturing is having the
server keep track of the score, what the down counter is, where the bar is, etc." The house
now sends both sides' short names and timeouts with every game event. `Scoreboard` reads ESPN's
down ("3rd & 15 at ARI 34") into the down, yards to go, where the ball is, yards to the end zone
and the line to gain ("ARI 19"). `game.playing` keeps all of it plus the timeouts, and the stage
note says: "Next: Seattle Seahawks have it, 4th and 7 at the ARI 26, 26 yards from the end zone,
the line to gain at the ARI 19. Timeouts left: Seattle Seahawks 2, Arizona Cardinals 3." A spot
on neither side by name, such as ESPN's ARZ, falls back to ESPN's own words.

**One play, told twice** (house 0.10.1, World 0.75.1). ESPN often tells one play in two or
three updates whose write-ups differ only by a leading space or a line break, and the first can
carry a garbled down: an incomplete pass came with "4th & 19 at SEA 38", then again with "2nd &
10". Beaky: "Oh, April, not on fourth down!" The house now compares write-ups ignoring spacing
(`GameStory.key`), so a repeat is no new play; the same play with another down is a correction
(`corrected: true`), which keeps `game.playing` right and opens no scene. `GameStory` collapses
repeated records into one play, takes "started from" from the last different play, and never
lists the play being told among the plays before it.

Known gap: a half's kickoff received by the side that had the ball at the half reads as a
first down, not a change of hands. The birds see the play, which says kickoff.

## Waiting for the TV (World 0.72.0, agent 2.109.0, #288)

The same afternoon: "They're responding 15s or so ahead of what I see on TV. I guess YouTube TV
has a delay vs ESPN's feed." Then: "I can just tell Beaky what the latency is of YouTube TV and
she sets it. Have it take effect for just one game."

1. **The bird keeps it.** The learning contract has a line for it:
   `[learned: the house | house.games_delay | 15 | today]`, the number of seconds the TV runs
   behind. It expires at the end of the day, which is one game; `none` ends it sooner. The
   librarian never files it.
2. **The World holds at its door.** While a delay is in force, a game event arriving from the
   house is not taken in. It is put on a world timer (`timer:game-held:<event id>`,
   purpose `game.held`) due that many seconds later, and the house is told `held` (HTTP 200,
   which the house reads as delivered). A world timer outlives a restart, so a held score
   isn't lost.
3. **The hold fires as the event it held.** `WorldTimerScheduler.firedEvent` hands back the
   house's own envelope, with its source, its id and ESPN's `occurred_at`, plus
   `held_seconds`. Then it goes in like any event: `game.playing` moves, and the scene opener
   hears it. Because the facts move only on release, a bird asked "what's the score?" during
   the delay knows only what April has seen.
4. **Still news.** The opener's old-news check allows `held_seconds` on top of
   `news_seconds`.
5. **Not held:** anything that isn't a game event, and an event the World already has (the
   house sending it again after release), which is the duplicate it always was.
6. **Viewer:** a pending hold is in the timers panel until it fires. A released event carries
   `held_seconds`, and its `received_at` minus its `occurred_at` is the lag.

Limits: at most 120 s, so "15 minutes" misheard can't hold the game for a quarter of an hour.
Changing the delay mid-game affects only events that arrive afterwards. Ones already held
keep their release time, so for a moment the order could differ from ESPN's.

## Not in this slice

- ~~**The birds bringing up a final unprompted.**~~ Built in World 0.69.0 (#276). After the
  Bears game April asked "No notice that the game ended?" A final now has its own stage note:
  "The game between Seattle Seahawks, the team April follows, and Chicago Bears is over:
  Seattle Seahawks lost, 17 to 34." It also has a `consider_on` line in the packaged
  `world.json`. Quiet hours hold, so a final after 23:00 is recorded and never announced.
- **The next game before game day.** Team Tracker publishes it 12 hours ahead.

## Tests

- `CreatureHouseTests`: Team Tracker states into events. Scores as strings, the minute-only date,
  and `team_winner` as a string are covered, along with:
  - `PRE` → `IN` → `POST` gives one of each event, and the final carries `ended_at`
  - a snapshot in `POST` gives a final with no `ended_at`, under the same key as a live one
  - unavailable and back again is not a second final
  - odds changing is nothing
  - `BYE` and `NOT_FOUND` give nothing
  - each score: by whom, the clock, a correction, the same score scored again after one, and
    both sides at once; a mid-game restart gives the game with its score, and no score event
- `CreatureWorldTests`:
  - the reducer's facts, words in the World's time zone, and what each event ends
  - through a real World, a live final then a snapshot final of the same game keeps the live
    `ended_at`
  - through the real page path, the game facts are on no page, even with the Seahawks named
- `WorldCoreTests`: a score asks the lead once in three minutes, and the trigger words for each
  kind of score
