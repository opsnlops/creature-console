# Creature MQTT Changelog

## 2.28.1 - 2026-06-12
- Version sync to 2.28.1 to stay aligned with the rest of the CLI tools (creature-cli added a creature-export command). No functional changes to creature-mqtt or creature-agent.

## 2.28.0 - 2026-06-12
- Align creature-mqtt and creature-agent to 2.28.0 to match the rest of the CLI tools.
- Fix `creature-agent` declaring `--trace-open-ai` twice (the compat alias collided with the auto-derived flag name), which made every invocation fail argument validation. The alias is now `--trace-openai`.

## 2.25.4 - 2026-06-09
- Align `MQTTMessageProcessor` with the server's ordered websocket ingestion pipeline.

## 2.20.0 - 2026-03-18
- Add distributed tracing with W3C trace context propagation.

## 2.19.10 - 2026-03-14
- Add request timeouts to the LLM clients and fix error reporting.

## 2.19.9 - 2026-03-14
- Fix a cooldown race condition in creature-agent.

## 2.19.8 - 2026-03-07
- Set a 10s timeout on local LLM health-check requests.

## 2.19.7 - 2026-03-07
- Use `cancelWhenGracefulShutdown` for the health-check loop.

## 2.19.6 - 2026-03-07
- Fix the health check blocking graceful shutdown.

## 2.19.5 - 2026-03-07
- Add a local LLM health check with OTel alerting support.

## 2.19.4 - 2026-03-07
- Fix slow SIGTERM shutdown in creature-agent and creature-mqtt.

## 2.19.3 - 2026-03-07
- Fix runaway local LLM generation with stop sequences.

## 2.19.2 - 2026-03-07
- Rename LM Studio references to generic local LLM naming.

## 2.19.1 - 2026-03-07
- Use backend-agnostic LLM naming in OTel spans, counters, and descriptions.

## 2.19.0 - 2026-03-07
- Add LM Studio backend support for creature-agent.

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
