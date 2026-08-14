# ──────────────────────────────────────────────────────────────────────────────
# Schema migration and cluster bootstrap.
#
# Two one-off task definitions, never attached to a service. Run them with
# `aws ecs run-task` — see the deployment guide in app/README.md.
#
#   <name>-schema : creates the temporal / temporal_visibility databases on the
#                   existing RDS instance and brings both schemas to the version
#                   required by the pinned server image. Must run BEFORE the
#                   server services start, and again before every server upgrade.
#
#   <name>-admin  : admin-tools with a frontend address configured. Registers the
#                   default namespace, and doubles as the shell for ad-hoc
#                   `temporal` / `tctl` commands against the cluster.
#
# Both are idempotent and safe to re-run.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "schema" {
  name              = "/aws/ecs/${var.name}/schema"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

locals {
  schema_migration_script = <<-EOT
    set -eu

    TLS_ARGS=""
    if [ "$${TEMPORAL_SQL_TLS:-false}" = "true" ]; then
      TLS_ARGS="--tls --tls-disable-host-verification"
    fi

    SCHEMA_ROOT="$TEMPORAL_SCHEMA_DIR"
    if [ ! -d "$SCHEMA_ROOT" ]; then
      echo "FATAL: schema directory $SCHEMA_ROOT not found in this admin-tools image." >&2
      echo "       Available:" >&2
      ls -d /etc/temporal/schema/postgresql/*/ >&2 || true
      exit 1
    fi

    # SQL_USER and SQL_PASSWORD are injected from Secrets Manager and read
    # natively by temporal-sql-tool, so no credential appears on the argv.
    run_sql() {
      temporal-sql-tool --plugin postgres12 --ep "$SQL_HOST" -p "$SQL_PORT" $TLS_ARGS "$@"
    }

    # `timeout` bounds the first connection attempt. Without it a stopped RDS
    # instance takes ~4.5 minutes to surface as a TCP timeout, per step.
    TIMEOUT=""
    if command -v timeout >/dev/null 2>&1; then
      TIMEOUT="timeout 45"
    fi

    # Connectivity is proven separately from the idempotency guards below.
    #
    # Those guards (`|| echo ...`) cannot tell "already exists" from "could not
    # connect", so on an unreachable database every step reported success while
    # writing nothing, and the task exited 0 after 10+ minutes of stacked
    # timeouts. This probe inspects the actual error text and refuses to continue
    # on a connection failure — only a genuine "already exists" is tolerated.
    echo "==> verifying $SQL_HOST:$SQL_PORT is reachable"
    set +e
    probe=$($TIMEOUT temporal-sql-tool --plugin postgres12 --ep "$SQL_HOST" \
      -p "$SQL_PORT" $TLS_ARGS --db "$TEMPORAL_DB" create 2>&1)
    probe_rc=$?
    set -e
    [ -n "$probe" ] && echo "$probe"

    if [ "$probe_rc" -eq 124 ]; then
      echo "FATAL: timed out connecting to $SQL_HOST:$SQL_PORT." >&2
      probe="connection timed out"
    fi

    case "$probe" in
      *"no usable database connection"* | *"connection timed out"* | \
      *"connection refused"* | *"i/o timeout"* | *"no such host"*)
        echo "FATAL: cannot reach the database at $SQL_HOST:$SQL_PORT." >&2
        echo "       Most likely causes, in order:" >&2
        echo "         1. the RDS instance is STOPPED — check DBInstanceStatus;" >&2
        echo "            a stopped instance still resolves in DNS but has no ENI," >&2
        echo "            so connections time out rather than being refused" >&2
        echo "         2. the RDS security group does not allow 5432 from this task" >&2
        echo "         3. var.db_host points at the wrong endpoint" >&2
        exit 1
        ;;
    esac
    echo "    reachable"

    # setup-schema is the only remaining step tolerated to fail, and only because
    # re-running it on an initialised database is expected. update-schema is
    # fatal — it is the step that must actually apply.
    echo "==> ensuring database '$TEMPORAL_VISIBILITY_DB' exists"
    run_sql --db "$TEMPORAL_VISIBILITY_DB" create \
      || echo "    create returned non-zero; assuming it already exists"

    echo "==> core schema in '$TEMPORAL_DB'"
    run_sql --db "$TEMPORAL_DB" setup-schema -v 0.0 || echo "    setup-schema returned non-zero; assuming already initialised"
    run_sql --db "$TEMPORAL_DB" update-schema -d "$SCHEMA_ROOT/temporal/versioned"

    echo "==> visibility schema in '$TEMPORAL_VISIBILITY_DB'"
    run_sql --db "$TEMPORAL_VISIBILITY_DB" setup-schema -v 0.0 || echo "    setup-schema returned non-zero; assuming already initialised"
    run_sql --db "$TEMPORAL_VISIBILITY_DB" update-schema -d "$SCHEMA_ROOT/visibility/versioned"

    echo "==> schema migration complete"
  EOT

  namespace_bootstrap_script = <<-EOT
    set -eu

    echo "==> waiting for frontend at $TEMPORAL_ADDRESS"
    i=0
    until temporal operator cluster health >/dev/null 2>&1; do
      i=$((i + 1))
      if [ "$i" -ge 60 ]; then
        echo "FATAL: frontend not healthy after 5 minutes" >&2
        exit 1
      fi
      sleep 5
    done

    echo "==> registering namespace '$TEMPORAL_NAMESPACE'"
    if temporal operator namespace describe --namespace "$TEMPORAL_NAMESPACE" >/dev/null 2>&1; then
      echo "    namespace already exists; reconciling retention to $TEMPORAL_RETENTION"
      temporal operator namespace update \
        --namespace "$TEMPORAL_NAMESPACE" \
        --retention "$TEMPORAL_RETENTION"
    else
      temporal operator namespace create \
        --namespace "$TEMPORAL_NAMESPACE" \
        --retention "$TEMPORAL_RETENTION"
    fi

    temporal operator namespace describe --namespace "$TEMPORAL_NAMESPACE"
    echo "==> bootstrap complete"
  EOT
}

resource "aws_ecs_task_definition" "schema" {
  family                   = "${var.name}-schema"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_exec.arn
  task_role_arn            = aws_iam_role.server_task.arn

  runtime_platform {
    cpu_architecture        = var.server_cpu_architecture
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name       = "schema"
      image      = var.temporal_admin_tools_image
      essential  = true
      entryPoint = ["/bin/sh", "-c", local.schema_migration_script]

      environment = [
        {
          name  = "SQL_HOST"
          value = var.db_host
        },
        {
          name  = "SQL_PORT"
          value = tostring(var.db_port)
        },
        {
          name  = "TEMPORAL_SQL_TLS"
          value = tostring(var.db_tls_enabled)
        },
        {
          name  = "TEMPORAL_DB"
          value = var.temporal_db_name
        },
        {
          name  = "TEMPORAL_VISIBILITY_DB"
          value = var.temporal_visibility_db_name
        },
        {
          name  = "TEMPORAL_SCHEMA_DIR"
          value = var.temporal_schema_dir
        },
      ]

      secrets = [
        {
          name      = "SQL_USER"
          valueFrom = local.db_user_secret
        },
        {
          name      = "SQL_PASSWORD"
          valueFrom = local.db_password_secret
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.schema.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "schema"
        }
      }
    },
  ])

  tags = var.tags
}

resource "aws_ecs_task_definition" "admin" {
  family                   = "${var.name}-admin"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_exec.arn
  task_role_arn            = aws_iam_role.server_task.arn

  runtime_platform {
    cpu_architecture        = var.server_cpu_architecture
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name       = "admin"
      image      = var.temporal_admin_tools_image
      essential  = true
      entryPoint = ["/bin/sh", "-c", local.namespace_bootstrap_script]

      environment = [
        {
          name  = "TEMPORAL_ADDRESS"
          value = local.frontend_address
        },
        {
          name  = "TEMPORAL_CLI_ADDRESS"
          value = local.frontend_address
        },
        {
          name  = "TEMPORAL_NAMESPACE"
          value = var.temporal_default_namespace
        },
        {
          name  = "TEMPORAL_RETENTION"
          value = var.temporal_default_namespace_retention
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.schema.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "admin"
        }
      }
    },
  ])

  tags = var.tags
}
