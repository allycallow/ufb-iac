resource "aws_cloudwatch_log_group" "audio_processing" {
  name              = "/ecs/${terraform.workspace}-audio-processing"
  retention_in_days = 1
}

module "audio_processing_task_definition" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name        = "${terraform.workspace}-audio-processing"
  cluster_arn = var.ecs_cluster_arn

  create_service = false

  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  cpu    = 512
  memory = 1024

  container_definitions = {
    audio-processing = {
      cpu                    = 512
      memory                 = 1024
      essential              = true
      image                  = var.image_uri
      user                   = "0"
      readonlyRootFilesystem = false

      environment = []

      secrets = []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${terraform.workspace}-audio-processing"
          "awslogs-region"        = "eu-west-2"
          "awslogs-stream-prefix" = "audio-processing"
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

  task_exec_iam_role_name = "ecs-audio-processing-task-exec-role"
  task_exec_iam_role_policies = {
    exec_policy = aws_iam_policy.audio_processing_ecs_task_exec_policy.arn
  }
}
