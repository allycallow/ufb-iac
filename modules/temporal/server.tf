# ──────────────────────────────────────────────────────────────────────────────
# Temporal server. One ECS service per role in multi-role mode, or a single
# all-in-one task in single-node mode — see local.roles in main.tf.
#
# Written as raw task definitions with jsonencode() rather than through
# terraform-aws-modules/ecs//modules/service, for two reasons:
#   1. that module emits the container key as `entrypoint`, and the ECS API
#      expects `entryPoint` — this deployment depends on an entrypoint override
#      to resolve each task's ringpop broadcast address;
#   2. all four roles share one security group (see security-groups.tf), so the
#      module's per-service group creation is not wanted here.
#
# The Web UI and the Python worker have no such constraints and do go through
# the shared service module, matching the rest of the repo.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "server" {
  for_each = local.roles

  name              = "/aws/ecs/${var.name}/${each.key}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_ecs_task_definition" "server" {
  for_each = local.roles

  family                   = "${var.name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(each.value.cpu)
  memory                   = tostring(each.value.memory)
  execution_role_arn       = aws_iam_role.task_exec.arn
  task_role_arn            = aws_iam_role.server_task.arn

  runtime_platform {
    cpu_architecture        = var.server_cpu_architecture
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name      = each.key
      image     = var.temporal_server_image
      essential = true
      cpu       = each.value.cpu
      memory    = each.value.memory

      # Wraps the image's own entrypoint so TEMPORAL_BROADCAST_ADDRESS can be
      # set from the task's ENI address at start time.
      entryPoint = ["/bin/sh", "-c", local.server_entrypoint_script]

      environment = [
        for k in sort(keys(merge(local.server_common_env, { SERVICES = each.value.service }))) : {
          name  = k
          value = merge(local.server_common_env, { SERVICES = each.value.service })[k]
        }
      ]

      secrets = [
        {
          name      = "POSTGRES_USER"
          valueFrom = local.db_user_secret
        },
        {
          name      = "POSTGRES_PWD"
          valueFrom = local.db_password_secret
        },
      ]

      # In single-node mode one container serves every role, so it listens on all
      # four gRPC ports and the whole membership range.
      portMappings = coalesce(local.role_port_mappings, [
        {
          name          = "grpc"
          containerPort = each.value.grpc_port
          hostPort      = each.value.grpc_port
          protocol      = "tcp"
        },
        {
          name          = "membership"
          containerPort = each.value.membership_port
          hostPort      = each.value.membership_port
          protocol      = "tcp"
        },
      ])

      # The image renders its config template into /etc/temporal at start, so the
      # root filesystem cannot be read-only. It already runs as the unprivileged
      # `temporal` user.
      readonlyRootFilesystem = false

      # Give in-flight RPCs room to drain before SIGKILL.
      stopTimeout = 60

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.server[each.key].name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    },
  ])

  # each.key, not each.value.service: in single-node mode the latter is
  # "frontend,history,matching,worker" and ECS rejects commas in tag values.
  tags = merge(var.tags, { Role = each.key })
}

resource "aws_ecs_service" "server" {
  for_each = local.roles

  name            = "${var.name}-${each.key}"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.server[each.key].arn
  desired_count   = each.value.desired_count

  enable_execute_command = var.enable_execute_command
  propagate_tags         = "SERVICE"

  # Server roles stay on on-demand capacity. History in particular owns shard
  # leases, and a Spot reclaim forces a shard rebalance across the ring — the
  # saving is not worth the latency spike. The cluster's default strategy would
  # otherwise place half of these tasks on Spot.
  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 0
  }

  network_configuration {
    subnets          = var.private_subnets
    security_groups  = [aws_security_group.server.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.roles[each.key].arn
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  availability_zone_rebalancing = "ENABLED"

  # each.key, not each.value.service: in single-node mode the latter is
  # "frontend,history,matching,worker" and ECS rejects commas in tag values.
  tags = merge(var.tags, { Role = each.key })

  depends_on = [
    aws_vpc_security_group_egress_rule.server_all,
    aws_iam_role_policy_attachment.task_exec_db_secret,
  ]
}
