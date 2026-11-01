# Self-hosted stand-in for the managed ElastiCache replication group (see
# modules/database's `manage_redis` toggle), used pre-launch to cut cost
# while there's no real traffic. No persistent volume: cache data loss on
# restart is acceptable, same call already made for Kafka's EBS volume on
# scale-to-zero.
module "redis_task_definition" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name                 = "${var.name}-redis"
  cluster_arn          = var.ecs_cluster_arn
  force_new_deployment = true

  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  cpu    = 256
  memory = 512

  # Brand new service with no real-world state to protect (see
  # modules/radio/ecs.tf for the same reasoning) - just start at zero.
  # Bump to 1 before a test session, back to 0 after.
  desired_count      = 0
  enable_autoscaling = false

  container_definitions = {
    redis = {
      cpu                                    = 256
      memory                                 = 512
      essential                              = true
      image                                  = "redis:7-alpine"
      readonlyRootFilesystem                 = false
      cloudwatch_log_group_retention_in_days = 1

      portMappings = [
        {
          name          = "redis"
          containerPort = 6379
          hostPort      = 6379
          protocol      = "tcp"
        }
      ]

      enable_cloudwatch_logging = true
    }
  }

  subnet_ids = var.private_subnets

  service_connect_configuration = {
    enabled   = true
    namespace = var.service_connect_namespace
    service = [{
      port_name      = "redis"
      discovery_name = "redis-sc"
      client_alias = {
        dns_name = "redis"
        port     = 6379
      }
    }]
  }

  security_group_ingress_rules = {
    for idx, sg_id in var.client_security_group_ids : "client_${idx}_redis" => {
      type                         = "ingress"
      from_port                    = 6379
      to_port                      = 6379
      protocol                     = "tcp"
      description                  = "Allow Redis traffic from client service"
      referenced_security_group_id = sg_id
    }
  }

  security_group_egress_rules = {
    all = {
      type        = "egress"
      from_port   = 0
      to_port     = 65535
      protocol    = "-1"
      description = "Allow traffic anywhere"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  create_task_exec_iam_role = true
  task_exec_iam_role_name   = "${var.name}-redis-exec"
  task_exec_iam_role_policies = {
    exec_policy = var.task_exec_policy_arn
  }

  tags = var.tags
}
