module "kafka_task_definition" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name                   = "${var.name}-kafka"
  cluster_arn            = var.ecs_cluster_arn
  force_new_deployment   = true
  enable_execute_command = true

  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  cpu    = var.cpu
  memory = var.memory

  capacity_provider_strategy = {
    FARGATE_SPOT = {
      capacity_provider = "FARGATE_SPOT"
      base              = 1
      weight            = 100
    }
  }

  volume = {
    "kafka-data" = {
      configure_at_launch = true
    }
  }

  volume_configuration = {
    name = "kafka-data"
    managed_ebs_volume = {
      size_in_gb       = 8
      volume_type      = "gp3"
      file_system_type = "ext4"
      encrypted        = true
    }
  }

  container_definitions = {
    kafka = {
      cpu                    = var.cpu
      memory                 = var.memory
      essential              = true
      image                  = "docker.redpanda.com/redpandadata/redpanda:v24.2.18"
      user                   = "0"
      readonlyRootFilesystem = false

      command = [
        "redpanda", "start",
        "--mode", "dev-container",
        "--smp", "1",
        "--memory", "${var.memory - 128}M",
        "--kafka-addr", "internal://0.0.0.0:9092",
        "--advertise-kafka-addr", "internal://kafka:9092",
        "--rpc-addr", "0.0.0.0:33145",
        "--advertise-rpc-addr", "kafka:33145"
      ]

      mountPoints = [
        {
          sourceVolume  = "kafka-data"
          containerPath = "/var/lib/redpanda/data"
          readOnly      = false
        }
      ]

      portMappings = [
        {
          name          = "kafka"
          containerPort = 9092
          hostPort      = 9092
          protocol      = "tcp"
        },
        {
          name          = "kafka-admin"
          containerPort = 9644
          hostPort      = 9644
          protocol      = "tcp"
        }
      ]

      enable_cloudwatch_logging = true
    }
  }

  subnet_ids               = var.private_subnets
  autoscaling_max_capacity = 1
  desired_count            = 1

  service_connect_configuration = {
    enabled   = true
    namespace = var.service_connect_namespace
    service = [
      {
        port_name      = "kafka"
        discovery_name = "kafka-sc"
        client_alias = {
          dns_name = "kafka"
          port     = 9092
        }
      }
    ]
  }

  security_group_ingress_rules = {
    for idx, sg_id in var.client_security_group_ids : "client_${idx}_kafka" => {
      type                         = "ingress"
      from_port                    = 9092
      to_port                      = 9092
      protocol                     = "tcp"
      description                  = "Allow Kafka traffic from client service"
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
  task_exec_iam_role_name   = "${var.name}-kafka-exec"
  task_exec_iam_role_policies = {
    exec_policy = var.task_exec_policy_arn
  }

  tags = var.tags
}
