# Each test run gets its own database (#247)

Every MongoDB test wrote into one `creature_world` and left its rows there. By 2026-10-24 the
local one held 68 MB from weeks of runs. Queries that read across a whole collection then found
other runs' rows in place of their own:
- **`DaylightRuleTests`:** the newest 50 light readings across every place.
- **`LearningThatLastsTests`:** every overwritten keeping, more than its limit of 500.
- **`HousePresenceTests`:** every order's status.
- **The end-to-end test:** the scene opener slowed from 1.1 s to 1.5 s a scene, with the house's
  situation reading every test order. That lost a race (#266).

Each test was right about its own rows. The database just wasn't its own.

## The change

1. **`TestDatabase.uri`** (CreatureWorldTests) is `MONGODB_TEST_URI`'s server and options with a
   database of the run's own: `creature_world_test_<unix seconds>_<random>`. Every MongoDB suite
   reads it in place of the environment, and the end-to-end test hands it to the World binary.
   A run starts empty. Each connection runs the migrations as it always has.
2. **The World accepts a test run's database.** It accepts the name `creature_world` (as
   before) or a name beginning `creature_world_test_`
   (`CreatureWorldConfiguration.isWorldDatabase`), in both the configuration check and the
   connection check. Production keeps `creature_world`, and the guard still refuses any other
   database.
3. **Old runs are dropped.** When a run starts, test databases more than a day old are dropped,
   best effort. A run going on at the same time is never dropped.
4. **A suite that runs a live World gets a database of its own within the run.** That is the
   black-box test and the application restart. A live World's rules sweep everything they can
   see: the restart test's delivery sweep settled `HousePresenceTests`' orders before that test's
   own sweep could (`TestDatabase.isolated(_:)`).
5. **The dropped-connection tests stop depending on the machine's speed.** CI's Tests workflow
   failed 34 of its last 40 runs, on `DroppedConnectionRetryTests` (since 10-17). A request is
   sent again only if its connection failed faster than `droppedBeforeRead` (50 ms). That is
   right for Creature Server: a start takes about 60 ms, so a faster drop never reached a
   handler. But on the CI runner the test server's drop took longer than 50 ms, so it wasn't
   resent. `execute` now takes the bound as `fastDrop`, and the tests, whose server never reads,
   allow 5 s. A new test holds the bound itself: a drop 200 ms after the request was read is
   never sent again.

   Separately, on macOS CI the reset came as Network.framework's own
   `NWError.posix(.ECONNRESET)`, which the World did not count as a drop. It does now. That one
   is a real fix: Creature Server can drop a connection that way.
6. **Nothing else is touched.** The old shared `creature_world` on the laptop is left alone; it
   is April's to drop.

## Versions

World 0.64.6: the database guard, and a reset reported by Network.framework is a dropped connection. Tests otherwise.
