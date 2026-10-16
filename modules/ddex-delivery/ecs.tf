resource "aws_cloudwatch_log_group" "ddex_ingest" {
  name              = "/ecs/${terraform.workspace}-ddex-ingest"
  retention_in_days = 1
}

module "ddex_ingest_task_definition" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name        = "${terraform.workspace}-ddex-ingest"
  cluster_arn = var.ecs_cluster_arn

  create_service = false

  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  cpu    = 512
  memory = 1024

  container_definitions = {
    ddex-ingest = {
      cpu                    = 512
      memory                 = 1024
      essential              = true
      image                  = var.image_uri
      user                   = "0"
      readonlyRootFilesystem = false

      environment = [
        {
          name  = "SENTRY_ENVIRONMENT"
          value = "production"
        },
        {
          name  = "KAFKA_BOOTSTRAP_SERVERS"
          value = var.kafka_bootstrap_servers
        },
        {
          name  = "KAFKA_DDEX_DELIVERY_EVENTS_TOPIC"
          value = "ufb.ddex_delivery_events"
        },
        {
          name  = "DDEX_DELIVERIES_BUCKET"
          value = aws_s3_bucket.deliveries.id
        },
        {
          name  = "MEDIA_BUCKET"
          value = var.media_bucket_name
        },
      ]

      secrets = [
        {
          name      = "SENTRY_DSN"
          valueFrom = "arn:aws:secretsmanager:eu-west-2:${data.aws_caller_identity.current.account_id}:secret:prod/ufb/ddex-ingest-yTHLep:SENTRY_DSN::"
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${terraform.workspace}-ddex-ingest"
          "awslogs-region"        = "eu-west-2"
          "awslogs-stream-prefix" = "ddex-ingest"
        }
      }
    }
  }

  subnet_ids = var.private_subnets

  security_group_egress_rules = {
    all = {
      type        = "egress"
      from_port   = 0
      to_port     = 65535
      protocol    = "-1"
      description = "Allow all outbound"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  create_task_exec_iam_role = true

  tasks_iam_role_statements = [
    {
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:GetObjectTagging",
        "s3:PutObjectTagging",
      ]
      resources = ["${aws_s3_bucket.deliveries.arn}/*"]
    },
    {
      effect = "Allow"
      actions = [
        "events:PutEvents",
      ]
      resources = [var.event_bus_arn]
    },
    {
      # Stages a release's cover art into the media bucket under a
      # disposable prefix - see mapping.py/task.py in ufb-ddex-ingest and
      # ddex_deliveries.py:_set_cover_art in ufb/backend. Scoped to that
      # one prefix, not the whole bucket - this task has no reason to
      # touch anything else there.
      effect = "Allow"
      actions = [
        "s3:PutObject",
      ]
      resources = ["${var.media_bucket_arn}/pending-ddex-covers/*"]
    }
  ]

  task_exec_iam_role_name = "ecs-ddex-ingest-task-exec-role"
  task_exec_iam_role_policies = {
    exec_policy = aws_iam_policy.ddex_ingest_ecs_task_exec_policy.arn
  }
}
