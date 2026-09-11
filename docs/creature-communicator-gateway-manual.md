# Creature Communicator Gateway Manual

Creature Communicator Gateway is the narrow network boundary used by Beaky Communicator. It is an
independently built, versioned, packaged, and deployed service in the Creature monorepo. It does
not reason for Beaky and does not own conversation history.

## Service topology

The stable local ports are:

| Product | Port | API prefix |
| --- | ---: | --- |
| Creature Server | `8000` | existing Creature Server API |
| Creature World | `8001` | `/world/v1` |
| Creature Communicator Gateway | `8002` | `/communicator/v1` |

Beaky Communicator sends typed utterances, history requests, and live-stream requests only to the
gateway. The gateway forwards those operations over HTTP to Creature World. Creature World remains
the sole authority for MongoDB conversation persistence, ordering, and idempotency. The gateway
does not keep a second chat database.

```text
Beaky Communicator
    -> /communicator/v1 on gateway:8002
    -> /world/v1 on world:8001
    -> creature_world in MongoDB
```

The gateway and World may share a host and use loopback, or run on separate trusted-LAN hosts.
There is no application-layer credential on this private hop. For off-LAN access, the existing
ingress proxy validates the app-family API key before routing `/communicator` to the gateway.

## Configuration

Configuration precedence is command-line options, environment variables, JSON configuration, then
built-in defaults.

| Setting | JSON key | Environment | Command option | Default |
| --- | --- | --- | --- | --- |
| Bind host | `host` | `SERVER_HOSTNAME` | `--host`, `-H` | `127.0.0.1` |
| Bind port | `port` | `SERVER_PORT` | `--port`, `-p` | `8002` |
| World API | `world_url` | `CREATURE_WORLD_URL` | `--world-url` | `http://127.0.0.1:8001/world/v1` |

The packaged configuration is `/etc/creature/communicator-gateway.json`. `world_url` must be an
absolute HTTP or HTTPS URL without credentials, a query, or a fragment. Never put proxy API keys or
other secrets in this file.

## API and health

The current endpoints are:

| Endpoint | Purpose |
| --- | --- |
| `GET /communicator/v1/health` | Readiness; returns 503 while World is unavailable, without stopping the gateway process. |
| `POST /communicator/v1/conversations/{conversation_id}/utterances` | Forward one typed, bounded `PersonUtterance`. |
| `GET /communicator/v1/conversations/{conversation_id}/items` | Fetch bounded canonical history with `limit` and `after_item_id`. |
| `GET /communicator/v1/conversations/{conversation_id}/stream` | Stream World conversation SSE bytes for immediate multi-client updates. |
| `POST /communicator/v1/foreground-leases` | Acquire a short-lived foreground lease. |
| `PUT /communicator/v1/foreground-leases` | Renew a foreground lease. |
| `DELETE /communicator/v1/foreground-leases` | Best-effort release of a foreground lease. |

The gateway stays running when World is down. Conversation requests return a bounded 503 response,
and streaming clients reconnect. Once World recovers, the next readiness check/request succeeds and
clients reconcile the authoritative history. Request bodies and page sizes are bounded. Message
content, proxy credentials, and future APNs tokens must never appear in logs or telemetry.

## Development smoke test

Start MongoDB, World, and the gateway in separate terminals:

```bash
docker compose -f compose.creature-world.json up -d
cd Common && swift run creature-world
cd Common && swift run creature-communicator-gateway
curl --fail-with-body http://127.0.0.1:8002/communicator/v1/health
```

The Swift test suite also runs a real loopback HTTP test covering gateway readiness, utterance
submission, history, and SSE between a gateway instance and a World-shaped server.

Build a release binary for direct testing with:

```bash
./build_communicator_gateway.sh
```

On Linux, pass `--static`; the binary is copied atomically to
`communicator-gateway/creature-communicator-gateway`. `./build_deb.sh` produces the independent
`creature-communicator-gateway_0.1.2_<architecture>.deb` package alongside the repository.

## Observability

The executable uses the repository's shared OpenTelemetry bootstrap. Configure Honeycomb with the
same `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_EXPORTER_OTLP_HEADERS` environment variables documented
in the [Creature World manual](creature-world-manual.md). Use a distinct service name of
`creature-communicator-gateway`. AsyncHTTPClient propagates the active distributed trace context
from the gateway request into Creature World. Do not record utterance text or secrets as span
attributes.
