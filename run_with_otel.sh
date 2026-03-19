#!/usr/bin/env bash

# Run creature-cli (or creature-agent) with OTel tracing exported to Honeycomb.
#
# Usage:
#   ./run_with_otel.sh creature-cli creatures list
#   ./run_with_otel.sh creature-cli voice ad-hoc play --creature-id <id> "Hello!"
#   ./run_with_otel.sh creature-agent run --config-path /etc/creature-agent.yaml
#
# Traces will appear in your Honeycomb dataset under the service name
# "creature-cli" or "creature-agent".

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────
# Replace this with your real Honeycomb API key
# ──────────────────────────────────────────────────────────────────────
HONEYCOMB_API_KEY="${HONEYCOMB_API_KEY:-your-honeycomb-api-key-here}"

if [[ "${HONEYCOMB_API_KEY}" == "your-honeycomb-api-key-here" ]]; then
    echo "⚠️  Set HONEYCOMB_API_KEY before running this script." >&2
    echo "   export HONEYCOMB_API_KEY=hcaik_01abc..." >&2
    exit 1
fi

# ──────────────────────────────────────────────────────────────────────
# OTel environment variables consumed by swift-otel's OTLPHTTP exporter
# ──────────────────────────────────────────────────────────────────────
export OTEL_EXPORTER_OTLP_ENDPOINT="https://api.honeycomb.io"
export OTEL_EXPORTER_OTLP_HEADERS="x-honeycomb-team=${HONEYCOMB_API_KEY}"

# Run whatever was passed on the command line
exec "$@"
