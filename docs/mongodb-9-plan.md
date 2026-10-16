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

## The prod move (not yet scheduled)

Prod is leaving Docker as well as 8.3. Today it is a single-node replica set in the
`mongodb` container. After the move it is the **MongoDB Community Server 9.0.4 packages,
installed natively**, the way dev is. Because the install changes along with the version,
this is a **move by dump and restore**, not an in-place binary upgrade:

- It is the exact path dev proved: an 8.3 dump, restored into a fresh 9.0.4 with 0 failures.
- The container and its volume are left untouched, so rollback is just starting it again.
- The new server starts at FCV 9.0 at once. There is no 8.3 burn-in step, because the
  burn-in exists to keep a downgrade cheap, and the container already is the way back.

### Before the day

1. **Install** `mongodb-org` 9.0.4 from MongoDB's apt repository, plus
   `mongodb-database-tools` and `mongosh`. Don't start it yet: the container holds 27017.
2. **`/etc/mongod.conf`**: copy dev's (`replSetName: creature-world`, no auth), but set
   `bindIp` to what prod's container publishes today. Check `docker port mongodb`, and don't
   open it wider than it is now. Put `dbPath` on the disk that should hold the data.
3. **Port the backup job off Docker** (`scripts/backup-databases.sh`,
   `scripts/systemd/creature-backup.service`, `docs/backups.md`). Today it does `docker exec
   mongodb mongodump`, checks that the container is running, and its unit
   `Requires=docker.service`. Natively it runs the host's `mongodump` / `mongorestore
   --dryRun` against `MONGO_URI` directly. Keep the step timeouts: `timeout` on a host
   process kills the tool itself, which is simpler than the `docker exec` case the script
   works around. Test it on dev, which already looks like prod will, including the upload to
   B2 (to a scratch prefix, not the 15-day folder).

### The day

1. Stop the World, the agents and creature-server, so nothing writes.
2. **Dump**: run the nightly job by hand (the Docker version, one last time), and check the
   archives reach B2. Note the documents restored by its `--dryRun`.
3. `docker stop mongodb`, and disable its restart policy
   (`docker update --restart=no mongodb`) so it can't take 27017 back on a reboot.
4. `sudo systemctl enable --now mongod`, then
   `rs.initiate({_id: "creature-world", members: [{_id: 0, host: "<the host the services use>:27017"}]})`.
   The member's host must be the name the URIs in `/etc/default/creature-*` resolve.
5. **Restore** both archives (`mongorestore --archive --gzip`, as on dev). Compare the counts
   with step 2. Expect fewer only from the TTL indexes clearing expired data.
6. Start creature-server and the World. Check health. The World's migrations are already
   at 14, so it should start with nothing to do. Then start the agents and talk to the birds.
7. That night, check that the first native backup ran, passed its `--dryRun`, and reached B2.

**Rollback:** stop and disable `mongod`, then `docker start mongodb` (with `--restart`
put back). The container's data is exactly as it was at step 2. Anything written to 9
since then would be lost, so decide quickly.

**After a burn-in of a week or so,** remove the container and its volume. Until then they
are the rollback.

### Also moves with it

- **CI:** `.github/workflows/tests.yml` runs `mongo:8.3.8`. Move it to `mongo:9.0.4` in the
  same change, so the tests run on what prod runs. (A container is right for CI. Only prod
  goes native.)
- **Local tests:** the Docker container the Mongo suites use goes to 9.0.4 too.
- `docs/backups.md`, the restore notes, and the operations manual name the install and the
  version.
