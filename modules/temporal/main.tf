locals {
  # ── Topology ────────────────────────────────────────────────────────────────
  #
  # single-node collapses the four roles into one container. The Cloud Map name
  # is still `temporal-frontend`, so client configuration is identical in both
  # modes and switching between them needs no consumer change.

  single_node = var.deployment_mode == "single-node"

  roles = local.single_node ? {
    all = {
      service         = "frontend,history,matching,worker"
      cpu             = var.single_node_cpu
      memory          = var.single_node_memory
      desired_count   = 1
      grpc_port       = var.server_roles["frontend"].grpc_port
      membership_port = var.server_roles["frontend"].membership_port
    }
  } : var.server_roles

  role_dns_name = local.single_node ? {
    all = "temporal-frontend"
    } : {
    for key in keys(var.server_roles) : key => "temporal-${key}"
  }

  frontend_role_key  = local.single_node ? "all" : "frontend"
  frontend_grpc_port = local.roles[local.frontend_role_key].grpc_port

  # Cloud Map registers `<service>.<namespace>`, so the frontend is reachable
  # cluster-wide at e.g. temporal-frontend.production-ufb.internal:7233
  frontend_host    = "${aws_service_discovery_service.roles[local.frontend_role_key].name}.${var.service_discovery_namespace_name}"
  frontend_address = "${local.frontend_host}:${local.frontend_grpc_port}"

  # A single-node task serves every role, so it must listen on all four gRPC
  # ports and the whole membership range. In multi-role mode each task exposes
  # only its own pair.
  role_port_mappings = local.single_node ? concat(
    [
      for key, role in var.server_roles : {
        name          = "grpc-${key}"
        containerPort = role.grpc_port
        hostPort      = role.grpc_port
        protocol      = "tcp"
      }
    ],
    [
      for key, role in var.server_roles : {
        name          = "member-${key}"
        containerPort = role.membership_port
        hostPort      = role.membership_port
        protocol      = "tcp"
      }
    ],
    [
      {
        name          = "metrics"
        containerPort = var.metrics_port
        hostPort      = var.metrics_port
        protocol      = "tcp"
      }
    ],
  ) : null

  db_user_secret     = "${var.db_secret_arn}:username::"
  db_password_secret = "${var.db_secret_arn}:password::"

  # Every server role needs the full port map: the docker config template renders
  # all four role stanzas regardless of which one SERVICES selects.
  role_port_env = merge([
    for key, role in var.server_roles : {
      "${upper(role.service)}_GRPC_PORT"       = tostring(role.grpc_port)
      "${upper(role.service)}_MEMBERSHIP_PORT" = tostring(role.membership_port)
    }
  ]...)

  # Temporal's postgres plugin. `postgres12` is the current plugin for any
  # PostgreSQL 12 or newer, including the PG 18 instance in modules/database.
  db_env = {
    DB                = "postgres12"
    DB_PORT           = tostring(var.db_port)
    POSTGRES_SEEDS    = var.db_host
    DBNAME            = var.temporal_db_name
    VISIBILITY_DBNAME = var.temporal_visibility_db_name
  }

  # The config template guards TLS with `{{- if .Env.SQL_TLS_ENABLED }}`, and any
  # non-empty string is truthy in Go templates — so these keys are omitted
  # entirely rather than set to "false" when TLS is off.
  db_tls_env = var.db_tls_enabled ? {
    SQL_TLS                           = "true"
    SQL_TLS_ENABLED                   = "true"
    SQL_TLS_DISABLE_HOST_VERIFICATION = "true"
  } : {}

  server_common_env = merge(
    local.db_env,
    local.db_tls_env,
    local.role_port_env,
    {
      LOG_LEVEL          = var.temporal_log_level
      NUM_HISTORY_SHARDS = tostring(var.temporal_num_history_shards)

      # Bind to every interface; membership is advertised via the resolved ENI
      # address exported by the entrypoint wrapper below.
      BIND_ON_IP = "0.0.0.0"

      # Used by the internal worker role's own SDK client.
      PUBLIC_FRONTEND_ADDRESS = local.frontend_address
      TEMPORAL_ADDRESS        = local.frontend_address

      # The image's config template hard-defaults this path, but the file only
      # ships in the auto-setup image — `temporalio/server` does not contain it,
      # and the server refuses to start without it. Pinned here so the entrypoint
      # wrapper below can create it deterministically.
      DYNAMIC_CONFIG_FILE_PATH = local.dynamic_config_path

      # Enables the server's built-in Prometheus metrics endpoint at /metrics.
      # Recognised directly by the image's config template — no config file
      # changes needed.
      PROMETHEUS_ENDPOINT = "0.0.0.0:${var.metrics_port}"
    },
  )

  # Under /tmp, not /etc/temporal: the image runs as the unprivileged `temporal`
  # user and /etc/temporal is root-owned, so the entrypoint cannot create the
  # file there.
  dynamic_config_path = "/tmp/temporal-dynamicconfig.yaml"

  # Resolves this task's ENI address and advertises it for ringpop membership.
  # Temporal writes the address to the cluster_membership table and peers dial it
  # directly, so it must be the real task IP — 0.0.0.0 or a DNS name will not do.
  # `hostname -i` returns the awsvpc ENI address; the task metadata endpoint is a
  # fallback for images without the hostname binary.
  server_entrypoint_script = <<-EOT
    set -eu

    # The server validates the dynamic config file at startup and refuses to boot
    # if it is missing. Only the auto-setup image ships one, so create an empty
    # map here — every dynamic config key then falls back to its built-in
    # default. Override individual keys by baking a real file into an image.
    if [ ! -f "$DYNAMIC_CONFIG_FILE_PATH" ]; then
      mkdir -p "$(dirname "$DYNAMIC_CONFIG_FILE_PATH")"
      echo '{}' > "$DYNAMIC_CONFIG_FILE_PATH"
      echo "created empty dynamic config at $DYNAMIC_CONFIG_FILE_PATH"
    fi

    ADDR="$(hostname -i 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | head -n1 || true)"
    if [ -z "$ADDR" ] && [ -n "$${ECS_CONTAINER_METADATA_URI_V4:-}" ]; then
      ADDR="$(curl -fsS "$ECS_CONTAINER_METADATA_URI_V4" | sed -n 's/.*"IPv4Addresses":\["\([0-9.]*\)".*/\1/p' | head -n1 || true)"
    fi
    if [ -z "$ADDR" ]; then
      echo "FATAL: could not resolve task IP for TEMPORAL_BROADCAST_ADDRESS" >&2
      exit 1
    fi
    export TEMPORAL_BROADCAST_ADDRESS="$ADDR"
    export POD_IP="$ADDR"
    echo "temporal[$SERVICES] advertising membership address $ADDR"
    exec /etc/temporal/entrypoint.sh
  EOT
}

# ──────────────────────────────────────────────────────────────────────────────
# Cloud Map service discovery
#
# Plain A records in the shared namespace created by modules/ecs-cluster. ECS
# registers and deregisters each task's ENI address as it starts and drains.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_service_discovery_service" "roles" {
  for_each = local.roles

  name        = local.role_dns_name[each.key]
  description = "Temporal ${each.value.service}"

  dns_config {
    namespace_id   = var.service_discovery_namespace_id
    routing_policy = "MULTIVALUE"

    dns_records {
      type = "A"
      ttl  = 15
    }
  }

  # Deliberately no health_check_custom_config. AWS has deprecated its only
  # attribute (failure_threshold), and an empty block is stored by AWS as null —
  # Terraform then reads that back as a difference and tries to REPLACE the
  # service on every apply, which collides with itself on the unique name.
  #
  # ECS registers and deregisters instances on task lifecycle either way; the
  # only thing given up is ECS propagating task health into Cloud Map, which
  # matters little for A records that disappear as soon as a task stops.

  force_destroy = true

  tags = var.tags
}

# The UI's own Cloud Map record. The only way in when create_ui_alb is false, and
# harmless (and useful for debugging) when an ALB is present.
resource "aws_service_discovery_service" "ui" {
  name        = "temporal-ui"
  description = "Temporal Web UI"

  dns_config {
    namespace_id   = var.service_discovery_namespace_id
    routing_policy = "MULTIVALUE"

    dns_records {
      type = "A"
      ttl  = 15
    }
  }

  # Deliberately no health_check_custom_config. AWS has deprecated its only
  # attribute (failure_threshold), and an empty block is stored by AWS as null —
  # Terraform then reads that back as a difference and tries to REPLACE the
  # service on every apply, which collides with itself on the unique name.
  #
  # ECS registers and deregisters instances on task lifecycle either way; the
  # only thing given up is ECS propagating task health into Cloud Map, which
  # matters little for A records that disappear as soon as a task stops.

  force_destroy = true

  tags = var.tags
}
