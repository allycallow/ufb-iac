# ──────────────────────────────────────────────────────────────────────────────
# Unleash feature-flag server on ECS Fargate.
#
# A single self-contained service: Unleash runs its own Knex schema migrations
# against its Postgres database on container boot, so — unlike Temporal —
# there is no separate one-off schema task in this module.
#
# Exposed on the shared public ALB (see alb.tf in the root), because the app
# and website evaluate flags directly against Unleash's Frontend API rather
# than through the backend. The admin UI rides the same listener; Unleash
# enforces its own login on every /api/admin and UI route, the same posture
# this repo already accepts for Airflow and the monitoring stack.
# ──────────────────────────────────────────────────────────────────────────────

locals {
  db_user_secret     = "${aws_secretsmanager_secret.db.arn}:username::"
  db_password_secret = "${aws_secretsmanager_secret.db.arn}:password::"
}

# Dedicated, non-rotating secret — same reasoning as Temporal's in this repo:
# RDS master credential auto-rotation must not be able to break a running
# Unleash task. This only generates the password; the Postgres role and
# database must still be created manually, once, against the master
# instance — see README.md.
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "db" {
  name = var.db_secret_name
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
  })
}

module "unleash" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 7.4"

  name                 = var.name
  cluster_arn          = var.ecs_cluster_arn
  force_new_deployment = true

  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  cpu           = var.cpu
  memory        = var.memory
  desired_count = var.desired_count

  # Fixed single instance by design (see var.desired_count) — not worth
  # autoscaling for flag-evaluation traffic, same reasoning as Temporal's UI
  # service in this repo.
  enable_autoscaling = false

  container_definitions = {
    unleash = {
      name      = "unleash"
      cpu       = var.cpu
      memory    = var.memory
      essential = true
      image     = var.image

      # Unleash writes nothing to disk; all state is in Postgres.
      readonlyRootFilesystem = var.readonly_root_filesystem

      portMappings = [
        {
          name          = "unleash"
          containerPort = var.port
          hostPort      = var.port
          protocol      = "tcp"
        },
      ]

      environment = [
        { name = "DATABASE_HOST", value = var.db_host },
        { name = "DATABASE_PORT", value = tostring(var.db_port) },
        { name = "DATABASE_NAME", value = var.db_name },
        # RDS Postgres 15+ forces SSL (rds.force_ssl). rejectUnauthorized:false
        # mirrors the TLS posture already accepted for Temporal in this repo
        # (SQL_TLS_DISABLE_HOST_VERIFICATION) — encrypted in transit, without
        # pinning the RDS CA bundle into the image.
        { name = "DATABASE_SSL", value = jsonencode({ rejectUnauthorized = false }) },
        { name = "LOG_LEVEL", value = upper(var.log_level) },
        { name = "NODE_ENV", value = "production" },
      ]

      # No UNLEASH_DEFAULT_ADMIN_* here: the admin account was created by hand
      # through the UI on first boot, and those env vars only ever affect a
      # truly empty users table — they'd be a no-op now anyway.
      secrets = [
        { name = "DATABASE_USERNAME", valueFrom = local.db_user_secret },
        { name = "DATABASE_PASSWORD", valueFrom = local.db_password_secret },
      ]

      enable_cloudwatch_logging              = true
      cloudwatch_log_group_retention_in_days = var.log_retention_days
    }
  }

  subnet_ids = var.private_subnets

  load_balancer = {
    service = {
      target_group_arn = var.alb_target_group_arn
      container_name   = "unleash"
      container_port   = var.port
    }
  }

  # Lets monitoring (and any future in-cluster consumer) reach Unleash as
  # unleash:4242 without a round trip through the public ALB.
  service_connect_configuration = {
    enabled   = true
    namespace = var.service_connect_namespace
    service = [{
      port_name      = "unleash"
      discovery_name = "unleash-sc"
      client_alias = {
        dns_name = "unleash"
        port     = var.port
      }
    }]
  }

  security_group_ingress_rules = {
    alb = {
      type                         = "ingress"
      from_port                    = var.port
      to_port                      = var.port
      protocol                     = "tcp"
      description                  = "Public ALB - admin UI, admin API, and the Frontend API the app/website call"
      referenced_security_group_id = var.alb_security_group_id
    }

    monitoring = {
      type                         = "ingress"
      from_port                    = var.port
      to_port                      = var.port
      protocol                     = "tcp"
      description                  = "Prometheus scrape of /internal-backstage/prometheus"
      referenced_security_group_id = var.monitoring_security_group_id
    }
  }

  security_group_egress_rules = {
    all = {
      type        = "egress"
      from_port   = 0
      to_port     = 65535
      protocol    = "-1"
      description = "Postgres, ECR, Secrets Manager, CloudWatch Logs"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  create_task_exec_iam_role = true
  task_exec_iam_role_name   = "${var.name}-task-exec"
  task_exec_iam_role_policies = {
    shared  = var.task_exec_policy_arn
    secrets = aws_iam_policy.secret_read.arn
  }

  tags = var.tags
}
