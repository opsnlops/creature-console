# House scene descriptions (#241)

April: "Let's do the scene descriptions next."

On the first live run of the house tag (#240), "Beaky, make it cozy in here" got "Would you like
Low Key or Sleepy Time?". Sleepy Time dims the *outside* lights, to be polite to the neighbors.
The bird had only the names.

## The change

1. **A store in the World.** `house_scenes`, one document per scene name: `description`,
   `askable` (whether a bird may ask for it), `updated_at`, `updated_by`.
   - **Seeds from config.** The packaged config's `house_scenes` is written at startup by
     `world:draft`. A draft that changes in the config replaces the stored draft, but never an
     edit April made: the same rule as the fact-meanings catalogue.
   - **`GET /v1/house/scenes`.** Every scene the house offers, with its note, plus any noted
     scene the house no longer offers (marked `offered: false`).
   - **`PUT /v1/house/scenes/{name}`.** Sets `{description, askable, updated_by}`.
2. **What a bird is told.** `GET /v1/house/asks` sends only the offered, askable scenes, with a
   `descriptions` map. The guard refuses a mind's request for a scene that isn't askable.
3. **The agent.** The contract lists each scene on its own line, "Sleepy Time: …". A scene with
   no description is listed by name. It stays in the stable item, so it's cached.
4. **The Viewer.** A House panel lists every scene: its description (edited in place), a "birds
   may ask" switch, and whether the house still offers it. Viewer 0.16.0.

## The drafts

Written by Claude from `ha-config/scenes/*.yaml`: April's top-of-file comments where there are
any, and otherwise the rooms each scene lights, how bright, the colors, and what it turns off
(fans, the family-room heat). Scenes run by automations are drafted as not askable: At
Sunrise, At Sunset, Carport Motion. So are the six wall-button scenes (the four Bunnys Room
ones and the two Family Room controller buttons). April: "Ignore the wall buttons, I don't use
those anymore. They were more trouble than they were worth." Blue Fire isn't in the YAML (only a script points at `scene.blue_fire`), so its
description is left for April. All of them go in `debian/creature-world.json` for April to
correct, in the config or in the Viewer.

## Versions

World 0.55.0, agent 2.95.0, Viewer 0.16.0.
