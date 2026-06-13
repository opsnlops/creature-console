# Database Migration CLI Utility — Implementation Plan

## Goal

Add a `creature-cli` utility that copies the creature server's MongoDB database from the
**mainstage** server (MongoDB 8) to the **travel** server (MongoDB 4.4), so the travel rig can
be loaded with the latest animations, creatures, playlists, etc. before going on the road.

## Approach

Use [MongoKitten](https://github.com/orlandos-nl/MongoKitten) (pure-Swift MongoDB driver,
builds on macOS and Linux, supports MongoDB 3.6+) to talk to both servers directly. Because
documents are copied as raw BSON `Document`s, nothing version-specific leaks between the
MongoDB 8 source and the 4.4 destination — the wire protocol (OP_MSG) is common to both.

## CLI Surface

```
creature-cli util migrate-database \
    --mainline-server mainstage.example.com \
    --travel-server travel.example.com
```

- `--mainline-server` (required): hostname/IP of the source (mainstage) MongoDB. May be a bare
  host, `host:port`, or a full `mongodb://` URI.
- `--travel-server` (required): hostname/IP of the destination (travel) MongoDB, same formats.
- `--database`: database name, defaults to `creature_server` (matches `DB_NAME` in
  creature-server's `config.h`).
- `--batch-size`: documents per `insertMany` batch (default 500).
- `--dry-run`: connect, list collections and counts, but write nothing.
- `--yes`: skip the interactive confirmation before overwriting the travel database.

## Migration Algorithm

1. Connect to both servers (fail fast with a clear message naming which side failed).
2. List collections on the source database.
3. Show a summary (collection names + document counts) and confirm before touching the
   destination (unless `--yes`).
4. For each collection:
   a. Drop the destination collection (travel mirrors mainstage exactly).
   b. Stream documents from the source in batches and `insertMany` into the destination.
   c. Re-create non-`_id` indexes on the destination.
5. Print a summary table of collections, documents copied, and indexes created.

## Code Layout

- `Common/Sources/CreatureCLI/databaseCommand.swift` — `CreatureCLI.Util.MigrateDatabase`
  subcommand with the orchestration logic.
- `Common/Sources/CreatureCLI/MongoServerAddress.swift` — small pure helper that normalizes
  the `--mainline-server` / `--travel-server` values into MongoDB connection URIs
  (bare host → `mongodb://host:27017`, `host:port` → `mongodb://host:port`, full URI passed
  through). Pure and unit-testable.
- `Common/Tests/CommonTests/MongoServerAddressTests.swift` — Swift Testing suite for the
  address normalization (bare host, host:port, IPv6, full URI, trailing slash, etc.).

## Dependency Changes

- Add `MongoKitten` (from: 7.16.0) to `Common/Package.swift`, **only** as a dependency of the
  `creature-cli` executable target — the GUI app and other tools don't need a Mongo driver.

## Compatibility Notes

- MongoKitten supports MongoDB 3.6+, so both 8.x and 4.4 are in range.
- Index options that exist in MongoDB 8 but not 4.4 are unlikely with creature-server's plain
  indexes; index creation failures are reported as warnings rather than aborting the copy.
- MongoKitten is pure Swift (NIO-based), so it builds on Linux; the Debian package products
  (`creature-cli`, `creature-mqtt`, `creature-agent`) must be verified in the Swift Linux
  container before tagging, per CLAUDE.md.

## Release Checklist

- swift-format all touched files.
- `cd Common && swift test`.
- Linux container build of the three packaged products.
- Bump marketing version + CLI `version` (2.27.0 — new feature), add `debian/changelog`
  entry, commit, tag.
