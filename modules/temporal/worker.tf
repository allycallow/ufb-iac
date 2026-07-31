# ──────────────────────────────────────────────────────────────────────────────
# Stateless Python worker fleet.
#
# Long-polls the frontend over gRPC and executes workflow and activity tasks.
# Nothing dials in, so the security group is egress-only and there is no target
# group. Scaling is CPU target-tracking with a deliberately long scale-in
# cooldown, and the fleet runs mostly on Fargate Spot: a reclaimed worker just
# stops polling, and Temporal redelivers its tasks to a surviving worker.
# ──────────────────────────────────────────────────────────────────────────────

locals {
  worker_environment = merge(
    {
      # The frontend's Cloud Map address. The SDK keeps one long-lived gRPC
      # channel here and re-resolves on reconnect.
      TEMPORAL_HOST       = local.frontend_address
      TEMPORAL_NAMESPACE  = var.temporal_default_namespace
      TEMPORAL_TASK_QUEUE = var.worker_task_queue

      WORKER_HEALTH_PORT            = tostring(var.worker_health_port)
      MAX_CONCURRENT_ACTIVITIES     = tostring(var.worker_max_concurrent_activities)
      MAX_CONCURRENT_WORKFLOW_TASKS = tostring(var.worker_max_concurrent_workflow_tasks)

      # Fargate Spot gives ~120s of notice; graceful_shutdown must finish inside
      # the container stopTimeout below.
      WORKER_GRACEFUL_SHUTDOWN_SECONDS = "90"
    },
    var.worker_environment,
  )
}

module "worker" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 7.4"

  name                   = "${var.name}-worker"
  cluster_arn            = var.ecs_cluster_arn
  force_new_deployment   = true
  enable_execute_command = var.enable_execute_command

  runtime_platform = {
    cpu_architecture        = var.worker_cpu_architecture
    operating_system_family = "LINUX"
  }

  cpu           = var.worker_cpu
  memory        = var.worker_memory
  desired_count = var.worker_desired_count

  capacity_provider_strategy = var.worker_use_spot ? {
    # `base` keeps a floor of on-demand tasks so a region-wide Spot squeeze
    # cannot take the whole fleet down.
    on_demand = {
      capacity_provider = "FARGATE"
      base              = var.worker_on_demand_base
      weight            = var.worker_on_demand_weight
    }
    spot = {
      capacity_provider = "FARGATE_SPOT"
      weight            = var.worker_spot_weight
    }
    } : {
    on_demand = {
      capacity_provider = "FARGATE"
      base              = 0
      weight            = 1
    }
  }

  enable_autoscaling       = true
  autoscaling_min_capacity = var.worker_min_capacity
  autoscaling_max_capacity = var.worker_max_capacity

  # CPU only. The module's default also adds a memory policy, which fights the
  # CPU policy on a worker whose memory sits flat while throughput varies.
  autoscaling_policies = {
    cpu = {
      policy_type = "TargetTrackingScaling"

      target_tracking_scaling_policy_configuration = {
        predefined_metric_specification = {
          predefined_metric_type = "ECSServiceAverageCPUUtilization"
        }

        target_value       = var.worker_cpu_target
        scale_in_cooldown  = var.worker_scale_in_cooldown
        scale_out_cooldown = var.worker_scale_out_cooldown
      }
    }
  }

  container_definitions = {
    worker = {
      name      = "worker"
      cpu       = var.worker_cpu
      memory    = var.worker_memory
      essential = true
      image     = var.worker_image_uri

      readonlyRootFilesystem = var.worker_readonly_root_filesystem

      environment = [
        for k in sort(keys(local.worker_environment)) : {
          name  = k
          value = local.worker_environment[k]
        }
      ]

      secrets = [
        for k in sort(keys(var.worker_secrets)) : {
          name      = k
          valueFrom = var.worker_secrets[k]
        }
      ]

      # Served in-process on the loopback interface by worker_main.py. It shares
      # the task's network namespace, so no security group rule is involved and
      # the port is not reachable from outside the task.
      healthCheck = {
        command     = ["CMD", "python", "/app/healthcheck.py"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 30
      }

      # Long enough for the SDK to drain in-flight activities on SIGTERM.
      stopTimeout = 120

      enable_cloudwatch_logging              = true
      cloudwatch_log_group_retention_in_days = var.log_retention_days
    }
  }

  subnet_ids = var.private_subnets

  create_security_group = false
  security_group_ids    = [aws_security_group.worker.id]

  create_task_exec_iam_role = true
  task_exec_iam_role_name   = "${var.name}-worker-exec"
  task_exec_iam_role_policies = merge(
    { shared = var.task_exec_policy_arn },
    length(var.worker_secret_arns) > 0 ? { secrets = aws_iam_policy.worker_secrets[0].arn } : {},
  )

  create_tasks_iam_role = true
  tasks_iam_role_name   = "${var.name}-worker-task"
  tasks_iam_role_policies = length(var.worker_secret_arns) > 0 ? {
    secrets = aws_iam_policy.worker_secrets[0].arn
  } : {}

  tags = var.tags

  depends_on = [
    aws_vpc_security_group_egress_rule.worker_all,
    aws_ecs_service.server,
  ]
}
