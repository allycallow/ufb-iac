module "frontend_task_definition" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name                 = var.name
  cluster_arn          = var.ecs_cluster_arn
  force_new_deployment = true

  cpu    = 1024
  memory = 2048

  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = {
    frontend = {
      cpu                    = 1024
      memory                 = 2048
      essential              = true
      image                  = var.image_uri
      user                   = "0"
      readonlyRootFilesystem = false

      portMappings = [
        {
          name          = "frontend"
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          "name" : "AMPLIFY_APP_ORIGIN",
          "value" : "https://production.upfrontbeats.com"
        },
        {
          "name" : "NEXT_PUBLIC_REACT_APP_ENDPOINT",
          "value" : "https://new-admin.upfrontbeats.com/graphql"
        },
        {
          "name" : "REACT_APP_ENDPOINT",
          "value" : "http://backend:8000/graphql"
        },
      ]

      secrets = []
    }
  }

  subnet_ids               = var.private_subnets
  autoscaling_max_capacity = 2

  load_balancer = {
    service = {
      target_group_arn = var.alb_target_group_arn
      container_name   = "frontend"
      container_port   = 3000
    }
  }

  service_connect_configuration = {
    enabled   = true
    namespace = var.service_connect_namespace
  }

  security_group_ingress_rules = {
    alb_ingress_3000 = {
      type                         = "ingress"
      from_port                    = 3000
      to_port                      = 3000
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

  create_task_exec_iam_role = true
  task_exec_iam_role_name   = "ecs-ufb-frontend-task-exec-role"
  task_exec_iam_role_policies = {
    exec_policy = var.task_exec_policy_arn
  }

  tags = var.tags
}
