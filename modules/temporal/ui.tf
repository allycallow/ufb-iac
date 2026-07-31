# ──────────────────────────────────────────────────────────────────────────────
# Temporal Web UI behind a dedicated internal ALB.
#
# The repo's root ALB is internet-facing. The Web UI is an unauthenticated
# administrative console over every workflow in the cluster, so it gets its own
# internal-only load balancer in the private subnets instead — reachable from
# inside the VPC and from whatever you list in ui_allowed_cidrs, and never from
# the internet. Route it through the existing Teleport application access for
# per-user identity, or terminate TLS here by setting ui_certificate_arn.
# ──────────────────────────────────────────────────────────────────────────────

module "alb" {
  count = var.create_ui_alb ? 1 : 0

  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name               = "${var.name}-ui"
  load_balancer_type = "application"
  internal           = true

  vpc_id  = var.vpc_id
  subnets = var.private_subnets

  enable_deletion_protection = var.ui_alb_deletion_protection

  security_group_ingress_rules = merge(
    {
      vpc = {
        from_port   = var.ui_port
        to_port     = var.ui_port
        ip_protocol = "tcp"
        description = "Temporal Web UI from within the VPC"
        cidr_ipv4   = var.vpc_cidr_block
      }
    },
    {
      for idx, cidr in var.ui_allowed_cidrs : "allowed_${idx}" => {
        from_port   = var.ui_port
        to_port     = var.ui_port
        ip_protocol = "tcp"
        description = "Temporal Web UI from an explicitly allowed range"
        cidr_ipv4   = cidr
      }
    },
    {
      for idx, sg in var.ui_client_security_group_ids : "client_${idx}" => {
        from_port                    = var.ui_port
        to_port                      = var.ui_port
        ip_protocol                  = "tcp"
        description                  = "Temporal Web UI from an in-cluster service"
        referenced_security_group_id = sg
      }
    },
  )

  security_group_egress_rules = {
    ui_tasks = {
      from_port   = var.ui_port
      to_port     = var.ui_port
      ip_protocol = "tcp"
      description = "Forward to Web UI tasks"
      cidr_ipv4   = var.vpc_cidr_block
    }
  }

  target_groups = {
    ui = {
      name_prefix                       = "tmprl-"
      backend_protocol                  = "HTTP"
      backend_port                      = var.ui_port
      target_type                       = "ip"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true

      health_check = {
        enabled             = true
        healthy_threshold   = 2
        interval            = 15
        matcher             = "200-399"
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 3
      }

      create_attachment = false
    }
  }

  listeners = {
    ui = {
      port            = var.ui_port
      protocol        = var.ui_certificate_arn == null ? "HTTP" : "HTTPS"
      certificate_arn = var.ui_certificate_arn
      ssl_policy      = var.ui_certificate_arn == null ? null : "ELBSecurityPolicy-TLS13-1-2-2021-06"

      forward = {
        target_group_key = "ui"
      }
    }
  }

  tags = var.tags
}

module "ui" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 7.4"

  name                   = "${var.name}-ui"
  cluster_arn            = var.ecs_cluster_arn
  force_new_deployment   = true
  enable_execute_command = var.enable_execute_command

  runtime_platform = {
    cpu_architecture        = var.server_cpu_architecture
    operating_system_family = "LINUX"
  }

  cpu           = var.ui_cpu
  memory        = var.ui_memory
  desired_count = var.ui_desired_count

  # Read-only console; no need for it to follow worker scaling.
  enable_autoscaling = false

  container_definitions = {
    ui = {
      name      = "ui"
      cpu       = var.ui_cpu
      memory    = var.ui_memory
      essential = true
      image     = var.temporal_ui_image

      readonlyRootFilesystem = var.ui_readonly_root_filesystem

      environment = [
        {
          name  = "TEMPORAL_ADDRESS"
          value = local.frontend_address
        },
        {
          name  = "TEMPORAL_UI_PORT"
          value = tostring(var.ui_port)
        },
        {
          name  = "TEMPORAL_DEFAULT_NAMESPACE"
          value = var.temporal_default_namespace
        },
        {
          name  = "TEMPORAL_NOTIFY_ON_NEW_VERSION"
          value = "false"
        },
      ]

      portMappings = [
        {
          name          = "ui"
          containerPort = var.ui_port
          hostPort      = var.ui_port
          protocol      = "tcp"
        },
      ]

      enable_cloudwatch_logging              = true
      cloudwatch_log_group_retention_in_days = var.log_retention_days
    }
  }

  subnet_ids = var.private_subnets

  # Shared group declared in security-groups.tf so the frontend's ingress rule
  # can reference it without a dependency cycle.
  create_security_group = false
  security_group_ids    = [aws_security_group.ui.id]

  load_balancer = var.create_ui_alb ? {
    ui = {
      target_group_arn = module.alb[0].target_groups["ui"].arn
      container_name   = "ui"
      container_port   = var.ui_port
    }
  } : {}

  # Always registered in Cloud Map. When there is no ALB this is the only way in,
  # at temporal-ui.<namespace>:8080. container_name/container_port are omitted
  # deliberately — they are only valid for SRV records, and this is an A record.
  service_registries = {
    registry_arn = aws_service_discovery_service.ui.arn
  }

  create_task_exec_iam_role = true
  task_exec_iam_role_name   = "${var.name}-ui-exec"
  task_exec_iam_role_policies = {
    shared = var.task_exec_policy_arn
  }

  tags = var.tags
}
