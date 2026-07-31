resource "aws_iam_policy" "ecs_task_exec_policy" {
  name        = "ecs-task-exec-secrets-policy"
  description = "Allow ECS task execution role to pull images, write logs, and get secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "${var.secret_prefix}*"
        ]
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_task_exec_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_task_exec_policy.arn
}

module "ecs_cluster" {
  source = "terraform-aws-modules/ecs/aws//modules/cluster"

  name = var.name

  task_exec_secret_arns = [
    "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:*"
  ]

  cluster_capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  # ── Default capacity provider strategy ──────────────────────────────────────
  #
  # The module's schema is map(object({ base, name, weight })) keyed by provider
  # name. This block previously wrapped those attributes in a second
  # `default_capacity_provider_strategy` level, which Terraform's object type
  # conversion silently DROPS rather than rejecting — so `weight = 50` and
  # `base = 20` never reached AWS. Both providers arrived with null attributes and
  # AWS substituted its own defaults; the live cluster read back as
  # FARGATE weight 1 / FARGATE_SPOT weight 1, base 0 on both. So the strategy was
  # functional but not what was written: an even split, with the intended
  # 20-task on-demand floor missing entirely.
  #
  # It went unnoticed because nothing consumes it: every ECS service in this repo
  # either sets `capacity_provider_strategy` explicitly or inherits the shared
  # service module's `launch_type = "FARGATE"` default, and an explicit
  # launch_type makes ECS ignore the cluster default entirely.
  #
  # This default now applies only to callers that specify neither — in practice
  # `ecs:RunTask` against the audio-processing and tm-processing task
  # definitions, which have `create_service = false` and are launched by Airflow
  # DAGs. Spot is preferred with on-demand as the fallback when a Spot pool is
  # exhausted. `base = 0` on both matters: a non-zero FARGATE base would send
  # every single-task RunTask call to on-demand.
  #
  # A service that must not run on Spot has to say so explicitly.
  default_capacity_provider_strategy = {
    FARGATE_SPOT = {
      weight = 99
      base   = 0
    }
    FARGATE = {
      weight = 1
      base   = 0
    }
  }
}

resource "aws_service_discovery_private_dns_namespace" "ecs" {
  name = "${var.name}.internal"
  vpc  = var.vpc_id
}
