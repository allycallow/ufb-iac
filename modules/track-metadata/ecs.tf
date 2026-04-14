resource "aws_cloudwatch_log_group" "track_metadata_processing" {
  name              = "/ecs/${terraform.workspace}-tm-processing"
  retention_in_days = 1
}

module "track_metadata_processing_task_definition" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name        = var.name
  cluster_arn = var.ecs_cluster_arn

  create_service = false

  runtime_platform = {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  cpu    = 512
  memory = 2048

  container_definitions = {
    tm-processing = {
      cpu                    = 512
      memory                 = 2048
      essential              = true
      image                  = var.image_uri
      user                   = "0"
      readonlyRootFilesystem = false

      environment = [
        {
          name  = "BACKEND_ENDPOINT"
          value = "https://new-admin.upfrontbeats.com"
        }
      ]

      secrets = [
        {
          name      = "BACKEND_API_KEY"
          valueFrom = "arn:aws:secretsmanager:eu-west-2:${data.aws_caller_identity.current.account_id}:secret:prod/ufb/backend-NKRahZ:API_KEY::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${terraform.workspace}-tm-processing"
          "awslogs-region"        = "eu-west-2"
          "awslogs-stream-prefix" = "tm-processing"
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
        "s3:*",
      ]
      resources = ["${var.media_bucket_arn}/*"]
    }
  ]

  task_exec_iam_role_name = "ecs-tm-task-exec-role"
  task_exec_iam_role_policies = {
    exec_policy = aws_iam_policy.track_metadata_processing_ecs_task_exec_policy.arn
  }
}
