# Database backups

Nightly at 04:30 (server time), `creature_server` and `creature_world` are dumped from the
MongoDB container (`mongodb`), checked, and uploaded to Backblaze B2. Each is kept **15 days**.
Script: `scripts/backup-databases.sh`. Issue: #219.

## What a night does

For each database:

1. `mongodump --archive --gzip` inside the container, streamed out to a temporary file.
2. **Checked:** the archive is replayed with `mongorestore --dryRun`, which reads every
   collection and writes nothing. A truncated or corrupt archive fails the night, not the day
   you need it.
3. Uploaded to `b2://creature-engineering/database/<db>/<db>-<UTC timestamp>.archive.gz`.
4. The temporary copy is removed.

Every dump and check runs under `timeout` *inside* the container (30 minutes, then killed 10
seconds later). A MongoDB that never answers would otherwise hang the job forever and silently
stop every backup after it. Any failure exits non-zero with the line that failed, so
`systemctl status creature-backup` and the journal show it.

## Retention: 15 days

B2 has no per-file expiry. The 15 days is a **lifecycle rule** on the bucket for the
`database/` prefix: a file is hidden 15 days after upload and deleted a day later. Updating a
bucket's lifecycle rules replaces all of them, so `--setup` reads the existing rules, keeps
every other one, and adds this one. The bucket holds other things too; the rule only ever
covers files under `database/`. Every nightly run checks the rule is still there and refuses
to back up (loudly) if it is not.

## Install (once, on the server)

```bash
# 1. b2 authorized for the user the timer runs as (april):
b2 account authorize            # key with read/write on creature-engineering

# 2. The script, and the retention rule:
sudo install -m 755 scripts/backup-databases.sh /usr/local/bin/creature-backup-databases
creature-backup-databases --setup
creature-backup-databases --check

# 3. A first backup by hand, then the timer:
creature-backup-databases
sudo install -m 644 scripts/systemd/creature-backup.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now creature-backup.timer
systemctl list-timers creature-backup.timer
```

Settings come from the environment, with these defaults: `CONTAINER=mongodb`,
`BUCKET=creature-engineering`, `PREFIX=database/`, `DATABASES="creature_server creature_world"`,
`KEEP_DAYS=15`, `STEP_TIMEOUT=1800`.

## Restore

```bash
b2 ls b2://creature-engineering/database/creature_world/          # pick one
b2 file download b2://creature-engineering/database/creature_world/creature_world-<stamp>.archive.gz world.archive.gz

# Into a scratch database first, to look before touching the real one:
docker exec -i mongodb mongorestore --archive --gzip \
    --nsFrom 'creature_world.*' --nsTo 'restored_world.*' < world.archive.gz

# Or over the real one (stop the services that write to it first):
docker exec -i mongodb mongorestore --archive --gzip --drop \
    --nsInclude 'creature_world.*' < world.archive.gz
```

## Notes

- A dump that has to be killed leaves a harmless zombie entry inside the container (MongoDB is
  PID 1 there and does not reap children). It holds no memory; restarting the container clears
  it.
- Tested 2026-10-02 against `mongo:7` with a stand-in `b2`: setup keeps existing rules and is
  idempotent; a night refuses without the rule; both databases dump, check, and upload; a hung
  dump fails in deadline + 10 s; an uploaded archive restored 500 of 500 documents.
