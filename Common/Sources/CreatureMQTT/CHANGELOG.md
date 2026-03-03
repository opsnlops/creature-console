# Creature MQTT Changelog

# Creature MQTT Changelog

## 2.18.2 - 2026-03-02
- Wire systemd env files to CLI flags so services use configured hosts instead of compiled-in defaults.
- Require env file for creature-mqtt and creature-agent systemd units (no more silent empty-string fallback).
- Install env file examples to `/etc/default/` via deb packages.

## 2.18.1 - 2026-03-02
- Extract `MQTTPublishing` protocol and `AgentEventProcessor` struct for testability.
- Add metrics test coverage for MQTTMessageProcessor counters (filtered, published, errors).
- Add metrics test coverage for AgentEventProcessor counters (received, skipped, cooldown, processed, speech, OpenAI errors).

## 2.18.0 - 2026-03-02
- Add OpenTelemetry observability (logs, traces, metrics) via swift-otel with OTLP/HTTP export to Honeycomb.
- Add metrics counters for messages published, publish errors, and filtered messages.
- Use ServiceGroup from swift-service-lifecycle for clean SIGTERM/SIGINT shutdown.
- Add EnvironmentFile support in systemd service for OTEL_* configuration.

## 2.15.8 - 2025-12-12
- Move Linux websocket client to SwiftNIO to resolve 100% CPU spin and handshake issues.
- Add verbose websocket and MQTT debug logging (payload previews, connection/close reasons).
- Retain MQTT publishes by default for easier Home Assistant consumption.

## 2.15.2 - 2025-12-10
- Flatten runtime topics to avoid duplicated activity/runtime sections; counters promoted to creature scope.
- Publish `animation_name` alongside `animation_id` using cached names with fetch-on-miss and cache reload on invalidation.
- Improve MQTT resilience: retry publishes after reconnect and update dedup cache only on successful sends.

## 2.15.1 - 2025-12-10
- Initial Debian package and bridge release; publishes Creature websocket events to MQTT with topic-level deduplication.
