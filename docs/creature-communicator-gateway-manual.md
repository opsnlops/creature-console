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
`creature-communicator-gateway_0.1.3_<architecture>.deb` package alongside the repository.

## Observability

The executable uses the repository's shared OpenTelemetry bootstrap. Configure Honeycomb with the
same `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_EXPORTER_OTLP_HEADERS` environment variables documented
in the [Creature World manual](creature-world-manual.md). Use a distinct service name of
`creature-communicator-gateway`. AsyncHTTPClient propagates the active distributed trace context
from the gateway request into Creature World. Do not record utterance text or secrets as span
attributes.

## Deployment handoff

PR #131 introduces a coordinated port and package transition: Creature World `0.1.12` defaults to
port `8001`, while Creature Communicator Gateway `0.1.3` defaults to port `8002`. Creature Server
continues to own port `8000`. Install and operate World and the gateway as independent products:

```bash
sudo apt install ./creature-world_0.2.1_amd64.deb
sudo apt install ./creature-communicator-gateway_0.1.3_amd64.deb
sudo systemctl enable --now creature-world.service
sudo systemctl enable --now creature-communicator-gateway.service
```

The packages intentionally do not start services during installation. Before enabling them, review
`/etc/creature/world.json` and `/etc/creature/communicator-gateway.json`. Package reinstall and
removal preserve administrator configuration.

On a shared host, the packaged loopback defaults are sufficient. If an ingress proxy runs on a
different trusted-LAN host, bind the gateway and/or World to the required LAN interface and use the
firewall as the boundary; do not add application-layer LAN authentication. Route `/world` to port
8001 and `/communicator` to port 8002.

After deployment, verify both private and ingress paths as applicable:

```bash
curl --fail-with-body http://127.0.0.1:8001/world/v1/health
curl --fail-with-body http://127.0.0.1:8002/communicator/v1/health
curl --fail-with-body https://server.prod.chirpchirp.dev/world/v1/health
curl --fail-with-body https://server.prod.chirpchirp.dev/communicator/v1/health
```

The gateway unit uses `After=creature-world.service`, not `Requires=`. It must remain running when
World is unavailable so clients receive an honest 503 and recover automatically when World returns.

Graceful shutdown (SIGTERM) cuts open Communicator streams itself: the stream handler cancels its
World relay, the response ends, and clients reconnect and reconcile history. A restart therefore
completes in well under a second even while a phone holds a stream open. The unit also sets
`TimeoutStopSec=15` so a regression can never hold a deploy for systemd's default 90 s.
`CommunicatorGatewayBlackBoxTests` launches the built executable against a World-shaped stub,
opens a stream, sends SIGTERM, and requires a clean exit within five seconds.
For the current branch, CI status and remaining product work are recorded in the dated handoff at
the top of [Beaky Virtual World](beakys-world.md).
