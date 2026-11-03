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

## Not in this slice

- **The birds bringing up a final unprompted.** A `game.final` opens no scene: no scene rule
  names it, and it is not storyworthy. When that comes, a final after 23:00 is recorded and
  never announced.
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
