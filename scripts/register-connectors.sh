#!/usr/bin/env bash
# Registers/updates every Kafka Connect connector config in
# modules/kafka-connect/connector-config/*.json against a running Connect
# worker's REST API. Run from somewhere with network access to the worker
# (e.g. via Teleport, or an ECS exec session into the kafka-connect task).
set -euo pipefail

KAFKA_CONNECT_URL="${KAFKA_CONNECT_URL:-http://kafka-connect:8083}"
CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../modules/kafka-connect/connector-config" && pwd)"

for config_file in "$CONFIG_DIR"/*.json; do
  name=$(jq -r .name "$config_file")
  echo "Registering ${name} from ${config_file}..."
  curl -sf -X PUT \
    -H "Content-Type: application/json" \
    -d "$(jq .config "$config_file")" \
    "${KAFKA_CONNECT_URL}/connectors/${name}/config" \
    | jq .
  echo
done
