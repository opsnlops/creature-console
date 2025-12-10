Creature MQTT bridge executable target. Mirrors the layout of `creature-cli` but publishes websocket events to MQTT for Home Assistant consumption.

## Usage
```
cd Common
swift run creature-mqtt bridge \
  --host server.prod.chirpchirp.dev \
  --mqtt-host home.opsnlops.io \
  --mqtt-port 1883 \
  --topic-prefix creatures \
  --log-level info
```

Key flags:
- `--mqtt-host`, `--mqtt-port`, `--mqtt-tls` control broker connectivity (default host `home.opsnlops.io`).
- `--retain` / `--no-retain` toggles retained messages (default: retain). IDs and names stay visible even after restarts when retained.
- `--topic-prefix` sets the root MQTT prefix (default: `creatures`).
- `--hide` / `--only` filter message types (see `--help` for values).
- `--seconds 0` runs until cancelled; set a value to auto-exit after N seconds.

## Topic shape
- Topic prefix: `creatures`
- Creature topics use the creature name slug when known; the UUID is published as an attribute (`<creature>/id`).
- Attributes are scalar, not JSON. Examples:
  - `creatures/<name>/sensors/board/temperature_f`
  - `creatures/<name>/sensors/board/power/vbus/voltage`
  - `creatures/<name>/runtime/activity/state`
  - `creatures/<name>/idle/enabled`
  - `system/counters/events_processed`

## Behavior
- Uses the existing Common websocket decoding; no new DTOs.
- Prefetches all creature names and resolves unknown UUIDs on the fly; caches them for later messages.
- Deduplicates per-topic values in memory to avoid re-publishing unchanged values.
- Swift 6 strict concurrency; MQTT client runs in an actor and topic cache uses locks for cross-actor safety.
