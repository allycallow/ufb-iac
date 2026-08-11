module "search_task_definition" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name        = var.name
  cluster_arn = var.ecs_cluster_arn

  # CircleCI owns the deployed task definition: it registers a new revision and
  # calls ecs update_service. Terraform's aws_ecs_task_definition tracks the
  # latest revision, so an apply pushes the service onto whichever revision
  # CircleCI registered last — a deployment Terraform has no business making.
  #
  # Unlike backend/frontend, the image tag here is `:latest` on both sides, so
  # the symptom is a revision change rather than an image rollback. The cause
  # and the fix are the same: keep Terraform out of the service's task
  # definition.
  #
  # NOTE: toggling this moves the service between two resource addresses inside
  # the upstream module (aws_ecs_service.this -> .ignore_task_definition), so it
  # requires a `terraform state mv`. Flipping it without that DESTROYS AND
  # RECREATES the service.
  ignore_task_definition_changes = true

  # Never deregister a task definition revision. The module defaults
  # track_latest = true, so a refresh snaps this resource onto a CircleCI-created
  # revision. Replacing it would then deregister that revision, and while
  # already-running tasks survive, ECS cannot start new ones from a deregistered
  # revision: task replacement and autoscaling would silently stop working.
  skip_destroy = true

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
        },
        {
          name          = "search-grpc"
          containerPort = 50051
          hostPort      = 50051
          protocol      = "tcp"
          appProtocol   = "grpc"
        }
      ]

      environment = [
        {
          name  = "OPENSEARCH_DOMAIN_ENDPOINT"
          value = aws_opensearch_domain.main.endpoint
        },
        {
          name  = "BACKEND_API_ENDPOINT"
          value = "https://new-admin.upfrontbeats.com"
        },
        {
          name  = "STAGE"
          value = "${terraform.workspace}"
        },
        {
          name  = "OTEL_EXPORTER_OTLP_ENDPOINT",
          value = "http://tempo:4317"
        },
        {
          name  = "OTEL_EXPORTER_OTLP_TIMEOUT",
          value = "30000"
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

  # CPU only: the module default also adds a memory policy, doubling alarm count for no benefit.
  autoscaling_policies = {
    cpu = {
      policy_type = "TargetTrackingScaling"
      target_tracking_scaling_policy_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ECSServiceAverageCPUUtilization"
        }
      }
    }
  }

  service_connect_configuration = {
    enabled   = true
    namespace = var.service_connect_namespace
    service = [
      {
        port_name      = "search"
        discovery_name = "search-sc"
        client_alias = {
          dns_name = "search"
          port     = 8000
        }
      },
      {
        port_name      = "search-grpc"
        discovery_name = "search-grpc-sc"
        client_alias = {
          dns_name = "search"
          port     = 50051
        }
      }
    ]
  }

  security_group_ingress_rules = {
    backend_ingress_8000 = {
      type                         = "ingress"
      from_port                    = 8000
      to_port                      = 8000
      protocol                     = "tcp"
      description                  = "Allow traffic from backend service"
      referenced_security_group_id = var.backend_security_group_id
    }

    backend_ingress_50051 = {
      type                         = "ingress"
      from_port                    = 50051
      to_port                      = 50051
      protocol                     = "tcp"
      description                  = "Allow gRPC traffic from backend service"
      referenced_security_group_id = var.backend_security_group_id
    }

    teleport_ingress_8000 = {
      type                         = "ingress"
      from_port                    = 8000
      to_port                      = 8000
      protocol                     = "tcp"
      description                  = "Allow traffic from Teleport app service"
      referenced_security_group_id = var.teleport_security_group_id
    }

    teleport_ingress_50051 = {
      type                         = "ingress"
      from_port                    = 50051
      to_port                      = 50051
      protocol                     = "tcp"
      description                  = "Allow gRPC traffic from Teleport app service"
      referenced_security_group_id = var.teleport_security_group_id
    }

    monitoring_ingress_8000 = {
      type                         = "ingress"
      from_port                    = 8000
      to_port                      = 8000
      protocol                     = "tcp"
      description                  = "Allow traffic from monitoring service"
      referenced_security_group_id = var.monitoring_security_group_id
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
    {
      effect = "Allow"
      actions = [
        "es:ESHttpGet",
        "es:ESHttpPut",
        "es:ESHttpPost",
        "es:ESHttpDelete"
      ]
      resources = [
        "${aws_opensearch_domain.main.arn}/*"
      ]
    }
  ]

  create_task_exec_iam_role = true
  task_exec_iam_role_name   = "ecs-ufb-search-task-exec-role"
  task_exec_iam_role_policies = {
    exec_policy = aws_iam_policy.search_ecs_task_exec_policy.arn
  }
}
