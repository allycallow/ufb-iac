# ──────────────────────────────────────────────────────────────────────────────
# One-off task that creates the dedicated `unleash` Postgres role and database
# on the existing RDS instance. Never attached to a service — run it by hand
# with `aws ecs run-task` once, before the Unleash service first starts, and
# again after manually rotating the password in aws_secretsmanager_secret.db.
#
# The admin-tools pattern used for Temporal doesn't apply here: Unleash needs
# a plain Postgres role, not a Temporal schema, and the official admin-tools
# image has no `psql`. postgres:18-alpine does, and matches the RDS engine
# version this repo runs (modules/database).
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "db_bootstrap" {
  name              = "/aws/ecs/${var.name}/db-bootstrap"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

locals {
  db_bootstrap_script = <<-EOT
    set -eu

    export PGPASSWORD="$MASTER_PASSWORD"
    CONN="-h $PGHOST -p $PGPORT -U $MASTER_USER -d $PGDATABASE -v ON_ERROR_STOP=1"

    echo "==> verifying $PGHOST:$PGPORT is reachable"
    psql $CONN -tAc "select 1" >/dev/null
    echo "    reachable"

    echo "==> ensuring role '$NEW_USER' exists with the current password"
    psql $CONN <<-SQL
      DO \$\$
      BEGIN
        IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$NEW_USER') THEN
          EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '$NEW_USER', '$NEW_PASSWORD');
        ELSE
          EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', '$NEW_USER', '$NEW_PASSWORD');
        END IF;
      END
      \$\$;
    SQL

    echo "==> granting '$NEW_USER' to the master role, so it can own a database"
    # CREATE DATABASE ... OWNER requires the connecting role to be able to
    # SET ROLE to the target owner (Postgres 16+). The RDS master user is not
    # a member of a role it just created, so it cannot set it as an owner
    # without this grant.
    psql $CONN -tAc "GRANT \"$NEW_USER\" TO \"$MASTER_USER\";"

    echo "==> ensuring database '$NEW_DB' exists, owned by '$NEW_USER'"
    # CREATE DATABASE cannot run inside a transaction block, so it cannot go
    # through the DO $$ ... $$ block used for the role above. \gexec is the
    # documented way to make it conditional: the query yields the CREATE
    # DATABASE statement as a single text row only when the database is
    # missing, and \gexec then executes that row (or nothing).
    #
    # Must go through psql's stdin script parser, not -c: -c sends the whole
    # string to the server as one query and does not reliably recognise a
    # trailing backslash meta-command, which fails with a server-side syntax
    # error on the literal "\".
    psql $CONN <<-SQL
      SELECT 'CREATE DATABASE $NEW_DB OWNER $NEW_USER' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$NEW_DB') \gexec
    SQL

    echo "==> db-bootstrap complete"
  EOT
}

data "aws_iam_policy_document" "db_bootstrap_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_iam_role" "db_bootstrap_exec" {
  name               = "${var.name}-db-bootstrap-exec"
  assume_role_policy = data.aws_iam_policy_document.db_bootstrap_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "db_bootstrap_managed" {
  role       = aws_iam_role.db_bootstrap_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Scoped to exactly the two secrets this task needs — the RDS master
# credentials (to connect) and this module's own dedicated secret (to know
# what password to set). The long-running service's execution role
# deliberately cannot read the master secret; only this one-off task can.
resource "aws_iam_policy" "db_bootstrap_secret_read" {
  # name_prefix, not name — see the identical comment on aws_iam_policy.secret_read
  # in iam.tf for why a fixed name collides with itself on a description edit.
  name_prefix = "${var.name}-db-bootstrap-secret-read-"
  description = "Read the RDS master credentials and the dedicated unleash DB secret"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadBootstrapSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = [
          var.db_master_secret_arn,
          aws_secretsmanager_secret.db.arn,
        ]
      },
    ]
  })

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "db_bootstrap_secret_read" {
  role       = aws_iam_role.db_bootstrap_exec.name
  policy_arn = aws_iam_policy.db_bootstrap_secret_read.arn
}

resource "aws_security_group" "db_bootstrap" {
  name        = "${var.name}-db-bootstrap"
  description = "Unleash DB-bootstrap one-off task (egress only)"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-db-bootstrap" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "db_bootstrap_all" {
  security_group_id = aws_security_group.db_bootstrap.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Postgres, ECR, Secrets Manager, CloudWatch Logs"
}

resource "aws_ecs_task_definition" "db_bootstrap" {
  family                   = "${var.name}-db-bootstrap"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.db_bootstrap_exec.arn
  task_role_arn            = aws_iam_role.db_bootstrap_exec.arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name       = "db-bootstrap"
      image      = "postgres:18-alpine"
      essential  = true
      entryPoint = ["/bin/sh", "-c", local.db_bootstrap_script]

      environment = [
        { name = "PGHOST", value = var.db_host },
        { name = "PGPORT", value = tostring(var.db_port) },
        { name = "PGDATABASE", value = var.db_bootstrap_database },
        { name = "NEW_USER", value = var.db_username },
        { name = "NEW_DB", value = var.db_name },
      ]

      secrets = [
        { name = "MASTER_USER", valueFrom = "${var.db_master_secret_arn}:username::" },
        { name = "MASTER_PASSWORD", valueFrom = "${var.db_master_secret_arn}:password::" },
        { name = "NEW_PASSWORD", valueFrom = "${aws_secretsmanager_secret.db.arn}:password::" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.db_bootstrap.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "db-bootstrap"
        }
      }
    },
  ])

  tags = var.tags
}
