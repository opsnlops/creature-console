#!/usr/bin/env bash
#
# Backs up the creature databases to Backblaze B2, nightly (#219).
#
#   backup-databases.sh            dump, verify, and upload every database
#   backup-databases.sh --setup    once: add the 15-day lifecycle rule to the bucket
#   backup-databases.sh --check    verify the rule and the tools, and back nothing up
#
# MongoDB runs in Docker (container `mongodb`), so mongodump and mongorestore run inside it and
# nothing is installed on the host. Each database is dumped to a gzipped archive, replayed with
# `mongorestore --dryRun` to prove the archive reads end to end, then uploaded to
#
#   b2://creature-engineering/database/<db>/<db>-<UTC timestamp>.archive.gz
#
# Retention: B2 has no per-file TTL. Keeping 15 days is a lifecycle rule on the bucket, scoped
# to the `database/` prefix: a file is hidden 15 days after upload and deleted a day later.
# `--setup` adds that rule and keeps any others (a bucket update replaces all of a bucket's
# rules, so it is read, merged, and written back); every run checks the rule is still there and
# fails before dumping anything if it is not.
#
# Needs: docker access, and a b2 CLI (4.x) already authorized for the account
# (`b2 account authorize`) as the user this runs as. Any failure exits non-zero, so the systemd
# unit shows it - a backup that quietly stopped working is worse than none.

set -Eeuo pipefail
# Anything that fails unexpectedly says where, so the journal shows more than an exit code.
trap 'echo "backup: ERROR: line $LINENO: $BASH_COMMAND failed" >&2' ERR

CONTAINER="${CONTAINER:-mongodb}"
BUCKET="${BUCKET:-creature-engineering}"
PREFIX="${PREFIX:-database/}"
DATABASES="${DATABASES:-creature_server creature_world}"
KEEP_DAYS="${KEEP_DAYS:-15}"
MONGO_URI="${MONGO_URI:-mongodb://127.0.0.1:27017/?directConnection=true}"
# A dump or a check that hangs - mongodump waits forever on a server that never answers -
# would hang every night after it; each is cut off at this many seconds and the run fails.
STEP_TIMEOUT="${STEP_TIMEOUT:-1800}"

log() { echo "backup: $*"; }
# Runs a tool inside the container under `timeout`, there and not on the host: cutting off
# `docker exec` kills only the client and leaves the tool running in the container.
bounded_in() {
    local flags=()
    [[ "$1" == "-i" ]] && { flags=(-i); shift; }
    # Asked to stop at the deadline, then killed 10 seconds later: mongodump finishes its own
    # 30-second connection attempt before honoring a polite stop.
    docker exec "${flags[@]}" "$CONTAINER" timeout --kill-after=10 "$STEP_TIMEOUT" "$@"
}
fail() { echo "backup: ERROR: $*" >&2; exit 1; }

# The lifecycle rule this script owns, as B2 writes it back.
rule_json() {
    printf '{"daysFromHidingToDeleting": 1, "daysFromUploadingToHiding": %d, "fileNamePrefix": "%s"}' \
        "$KEEP_DAYS" "$PREFIX"
}

bucket_json() { b2 bucket get "$BUCKET"; }

# 0 when the bucket has a rule for $PREFIX hiding files after $KEEP_DAYS days.
has_rule() {
    bucket_json | python3 -c '
import json, sys
bucket = json.load(sys.stdin)
prefix, days = sys.argv[1], int(sys.argv[2])
ok = any(r.get("fileNamePrefix") == prefix and r.get("daysFromUploadingToHiding") == days
         for r in bucket.get("lifecycleRules") or [])
sys.exit(0 if ok else 1)' "$PREFIX" "$KEEP_DAYS"
}

check_tools() {
    command -v b2 >/dev/null || fail "the b2 CLI is not on PATH"
    command -v python3 >/dev/null || fail "python3 is not on PATH"
    docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -qx true \
        || fail "container '$CONTAINER' is not running"
    docker exec "$CONTAINER" mongodump --version >/dev/null \
        || fail "mongodump is not in container '$CONTAINER'"
    b2 bucket get "$BUCKET" >/dev/null \
        || fail "cannot read bucket '$BUCKET' - is b2 authorized for this user?"
}

setup() {
    check_tools
    if has_rule; then
        log "bucket $BUCKET already keeps $PREFIX for $KEEP_DAYS days"
        return
    fi
    local current type rules
    current="$(bucket_json)"
    type="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["bucketType"])' <<<"$current")"
    # Every other rule, as it was, then ours: one --lifecycle-rule per rule.
    mapfile -t rules < <(python3 -c '
import json, sys
prefix = sys.argv[1]
for rule in json.load(sys.stdin).get("lifecycleRules") or []:
    if rule.get("fileNamePrefix") != prefix:
        print(json.dumps(rule))' "$PREFIX" <<<"$current")
    rules+=("$(rule_json)")
    local args=()
    for rule in "${rules[@]}"; do args+=(--lifecycle-rule "$rule"); done
    b2 bucket update "${args[@]}" "$BUCKET" "$type" >/dev/null \
        || fail "b2 could not update bucket $BUCKET's lifecycle rules"
    has_rule || fail "set the lifecycle rule, but B2 does not show it"
    log "bucket $BUCKET now keeps $PREFIX for $KEEP_DAYS days (then deletes a day later)"
}

backup() {
    check_tools
    has_rule || fail "bucket $BUCKET has no ${KEEP_DAYS}-day rule for $PREFIX - run with --setup"

    local stamp
    stamp="$(date -u +%Y-%m-%dT%H%M%SZ)"
    # Global, so the trap still knows it when a failure exits from inside the loop.
    WORK="$(mktemp -d -t creature-backup.XXXXXX)"
    trap 'rm -rf "$WORK"' EXIT

    for db in $DATABASES; do
        local archive="$WORK/$db-$stamp.archive.gz"
        log "dumping $db"
        bounded_in mongodump --quiet --uri "$MONGO_URI" --db "$db" \
            --archive --gzip >"$archive" || fail "dumping $db failed or took over ${STEP_TIMEOUT}s"
        [[ -s "$archive" ]] || fail "$db dumped nothing"

        # Prove the archive reads end to end: a dry-run restore reads every collection and
        # writes nothing. A truncated or corrupt archive fails here, not on the day it is needed.
        bounded_in -i mongorestore --quiet --dryRun --archive --gzip \
            --uri "$MONGO_URI" <"$archive" \
            || fail "$db's archive does not restore cleanly"

        local name="${PREFIX}${db}/$(basename "$archive")"
        log "uploading $db ($(du -h "$archive" | cut -f1)) to b2://$BUCKET/$name"
        b2 file upload --no-progress "$BUCKET" "$archive" "$name" >/dev/null
        rm -f "$archive"
    done
    log "done: $DATABASES at $stamp"
}

case "${1:-}" in
    --setup) setup ;;
    --check) check_tools; has_rule || fail "no ${KEEP_DAYS}-day rule for $PREFIX"; log "ok" ;;
    "") backup ;;
    *) echo "usage: $0 [--setup | --check]" >&2; exit 2 ;;
esac
