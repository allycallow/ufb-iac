module "search_task_definition" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name        = var.name
  cluster_arn = var.ecs_cluster_arn

  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  cpu    = 512
  memory = 1024

  container_definitions = {
    search = {
      cpu                    = 512
      memory                 = 1024
      essential              = true
      image                  = var.image_uri
      user                   = "0"
      readonlyRootFilesystem = false

      portMappings = [
        {
          name          = "search"
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "OPENSEARCH_DOMAIN_ENDPOINT"
          value = "https://${var.opensearch_domain_endpoint}"
        },
        {
          name  = "BACKEND_API_ENDPOINT"
          value = "https://new-admin.upfrontbeats.com"
        },
        {
          name  = "STAGE"
          value = "${terraform.workspace}"
        }
      ]

      secrets = [
        {
          name      = "API_KEY"
          valueFrom = "${var.secret_prefix}:API_KEY::"
        },
        {
          name      = "BACKEND_API_KEY"
          valueFrom = "${var.secret_prefix}:BACKEND_API_KEY::"
        },
        {
          name      = "SENTRY_DSN"
          valueFrom = "${var.secret_prefix}:SENTRY_DSN::"
        },
        {
          name      = "BETTER_STACK_TOKEN"
          valueFrom = "${var.secret_prefix}:BETTER_STACK_TOKEN::"
        },
      ]
    }
  }

  subnet_ids               = var.private_subnets
  autoscaling_max_capacity = 2

  load_balancer = {
    service = {
      target_group_arn = var.alb_target_group_arn
      container_name   = "search"
      container_port   = 8000
    }
  }

  security_group_ingress_rules = {
    alb_ingress_8000 = {
      type                         = "ingress"
      from_port                    = 8000
      to_port                      = 8000
      protocol                     = "tcp"
      description                  = "Allow traffic from ALB"
      referenced_security_group_id = var.alb_security_group_id
    }
  }


  security_group_egress_rules = {
    all = {
      type        = "egress"
      from_port   = 0
      to_port     = 65535
      protocol    = "-1"
      description = "Allow traffic from anywhere"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  tasks_iam_role_statements = [
    {
      actions = [
        "secretsmanager:GetSecretValue"
      ]
      effect = "Allow"
      resources = [
        "${var.secret_prefix}:*"
      ]
    },
  ]

  create_task_exec_iam_role = true
  task_exec_iam_role_name   = "ecs-ufb-search-task-exec-role"
  task_exec_iam_role_policies = {
    exec_policy = aws_iam_policy.search_ecs_task_exec_policy.arn
  }
}
