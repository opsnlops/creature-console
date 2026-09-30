# Information Bridge telemetry plan

The Bridge is the one part of Beaky's World that Honeycomb cannot see. On 2026-09-28 a text
Jesse sent at 11:42 AM reached the world at 12:58 PM and made him "expected" again after April
had said he'd left, and there was no way to tell whether Messages delivered it late or the
Bridge read it late: the Bridge logs only to the Mac's unified log, on a laptop across the
house. The services configure OpenTelemetry from `OTEL_EXPORTER_OTLP_*` environment
variables; a GUI app started by launchd never sees them. So the Bridge's telemetry is
configured where everything else about it is: in Settings.

## 1. Shared bootstrap (Common/Observability)

- `Observability` becomes a library product, so the Bridge can link it like `WorldCore`.
- A second entry point beside the environment one, taking the exporter explicitly:
  `bootstrapObservability(serviceName:exporter:localLog:)` with an `OTLPExporterSettings`
  (base endpoint URL, headers). Per-signal endpoints are derived the way the spec derives them
  from `OTEL_EXPORTER_OTLP_ENDPOINT` (`/v1/traces`, `/v1/metrics`, `/v1/logs`), because
  swift-otel uses an endpoint set in code as-is. The environment path keeps working unchanged.
- The local half of the log multiplexer is the caller's: stderr for the services, the unified
  log (`LoggingOSLog`, already a dependency) for the Bridge, so Console.app still shows
  everything.
- No endpoint, no export: the Bridge with telemetry off behaves exactly as today.

## 2. Settings → Telemetry

- On/off, endpoint (default `https://api.honeycomb.io`), and the API key (sent as
  `x-honeycomb-team`). The key lives in the Keychain beside the mail passwords
  (`AfterFirstUnlock`), never in defaults. Service name: `information-bridge`.
- OpenTelemetry bootstraps once per process, so a change applies at the next launch; the
  section says so and offers **Relaunch** (the KeepAlive launch agent brings it straight back).

## 3. What the Bridge tells Honeycomb

Spans and logs through swift-log / swift-distributed-tracing, where the questions are:

- **Every source run** (mail, messages, calendar, reminders, weather, contacts): a span with
  what it read and what it cast.
- **Messages:** each text read carries `message.lag_seconds` - the poll's time minus the time
  Messages stamped on the text. A late text is then one query: a big lag with a steady poll is
  Messages delivering late; a gap between polls is the Bridge.
- **The outbox:** each send to the world, with the world's answer and how long it waited.
- **Heartbeat:** each `bridge.online` as a span, so a sleeping laptop is a visible gap.

The `os.Logger` calls stay for Console.app; the new spans are added beside them rather than
rewriting every log line.

## 4. Done means

A text April sends herself from a mapped contact shows up in Honeycomb as a messages-poll span
with its lag, next to the world's acceptance of the cast - and the Bridge with telemetry off
is byte-for-byte the Bridge of today.
