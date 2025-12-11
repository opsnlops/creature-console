# Creature MQTT Changelog

## 2.15.2 - 2025-12-10
- Flatten runtime topics to avoid duplicated activity/runtime sections; counters promoted to creature scope.
- Publish `animation_name` alongside `animation_id` using cached names with fetch-on-miss and cache reload on invalidation.
- Improve MQTT resilience: retry publishes after reconnect and update dedup cache only on successful sends.

## 2.15.1 - 2025-12-10
- Initial Debian package and bridge release; publishes Creature websocket events to MQTT with topic-level deduplication.
