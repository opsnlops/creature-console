# MongoDB 9: the dev test, and the road to prod

MongoDB 9.0 went GA at the start of October 2026. The reason to move is vector search
(`mongot`, deferred in #229): if retrieval ever needs it, it
should land on 9, not 8. This page records what the dev test proved, and the plan for prod.

## The dev server (2026-10-15)

- **Host:** `10.19.63.10`, MongoDB **9.0.4** installed natively by April (not Docker).
- **Config** (`/etc/mongod.conf`): `replication.replSetName: creature-world`,
  `net.bindIp: 127.0.0.1,10.19.63.10`, no auth, the same as prod.
- **Replica set:** `rs.initiate({_id: "creature-world", members: [{_id: 0, host: "10.19.63.10:27017"}]})`.
  It is a single node, because the World needs transactions and transactions need a replica set.
- **FCV:** `9.0`.
- **URI:** `mongodb://10.19.63.10:27017/creature_world?replicaSet=creature-world&directConnection=true`
  The World refuses any database name other than `creature_world`.

## What it proved

1. **The full Common test suite passes against 9.0.4**, including every Mongo-backed suite
   (`MONGODB_TEST_URI` pointed at the dev server).
   - One black-box test raced: it read a scene between the *opened* and *offered* writes.
     Across the network that read landed between them two runs in three. The test now waits
     for the floor, as its sibling already did. 5/5 runs on 9 after the fix, and it passes
     locally. This was a race in the test, not a difference in 9.
   - Speed: the World suites took 11.6 s on 9 against 28.4 s on local 8.3. This is **not**
     a benchmark. The 8.3 runs are Docker Desktop on a Mac, and 9 is native Linux on its
     own disk. A fair comparison would run both versions on the same host.
2. **The prod backup restores into 9 cleanly.** Last night's B2 archives (8.3 dumps):
   `creature_world` restored 467,544 documents and `creature_server` 887, with 0 failures.
   The counts afterwards were lower (463,464 and 137). That is the TTL indexes doing their
   job on expired data, not loss.
3. **A 0.51.0 World migrates and serves on 9.** It ran from a local build against the
   restored copy. Migration 14 (`fact_origin`) backfilled ~199k facts in about 22 minutes,
   one update per fact, so the network round trip set the pace. Prod's database is local
   to the World, so it will be much faster there.
   - Afterwards: `schema_migrations` reaches 14, the `fact_origins` index exists, health
     reports `0.51.0`, and every fact has `origin` or `origin_unknown`. The only exceptions
     are four `presence.region` facts written after start, and those carry no origin by design.
4. **The page is right.** Beaky's perspective for *"landings are still the hardest part of
   flying"* on dev holds `flight.hardest_part = landings`, the flight-training fact and the
   September 27 episode, the same as prod. Everything else that differs comes from the copy:
   no live house readings, and no birds logged in.

## Compatibility review (Compatibility Changes in MongoDB 9.0)

Nothing in it touches us:

- **Change streams:** an election now interrupts `getMore`. We don't use change streams.
- **Cross-database `renameCollection`** now locks both collections. We don't rename.
- **Server-side JS** changes (`$where`, `$function`, `mapReduce`, ppc64le, UTC dates):
  we use none of it.
- **`$group`** with an empty accumulator field name now errors: none of ours have one.
- **Queryable Encryption preview removed:** not used.
- **Driver:** MongoKitten `7.16.3-opsnlops.1`, our fork, verified by the suite above.

## The prod upgrade (not yet scheduled)

From *Upgrade 8.3 Replica Set to 9.0*: the path is 8.3 (or 8.0) → 9.0, and the FCV must be
**8.3** before the binaries change. Prod is a single-node replica set in the `mongodb` Docker
container, so there are no secondaries to roll through. The upgrade is one restart.

1. **Check the FCV is 8.3**:
   `db.adminCommand({getParameter: 1, featureCompatibilityVersion: 1})`.
   If it is lower, run `setFeatureCompatibilityVersion: "8.3", confirm: true` and wait.
2. Check `rs.status()`: the member is `PRIMARY`, not `RECOVERING` or `ROLLBACK`.
3. **Take a fresh backup** with the nightly job, by hand, and check it reaches B2.
   Stop the World, the agents and creature-server first, so the dump is quiet.
4. Stop the container and change the image to `mongo:9.0.4`. Start it on the same volume.
5. Check that health is ok, and that the World and creature-server start and serve. Talk to
   the birds.
6. **Burn in on FCV 8.3** for a few days. A downgrade to 8.3 stays simple until the FCV is raised.
7. Then `db.adminCommand({setFeatureCompatibilityVersion: "9.0", confirm: true})`. It adds
   `term` to the replica set config and is idempotent if it has to be retried.

**Rollback** before step 7: put the 8.3 image back on the same volume. After step 7: follow
*Downgrade 9.0 to 8.3* (lower the FCV first), or restore the step 3 backup.

### Also moves with it

- **CI:** `.github/workflows/tests.yml` runs `mongo:8.3.8`. Move it to `mongo:9.0.4` in the
  same change, so the tests run on the version prod runs.
- **Local tests:** the Docker container the Mongo suites use goes to 9.0.4 too.
- **Backups:** the nightly job runs `mongodump` inside the container, so the tools come
  from the new image. After the upgrade, check the first night's archive and its
  `--dryRun` replay.
- `docs/backups.md` and the restore notes name the version.
