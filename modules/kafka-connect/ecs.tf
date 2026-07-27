locals {
  connect_distributed_properties = <<-EOF
    bootstrap.servers=kafka:9092
    group.id=${var.name}-kafka-connect

    config.storage.topic=_connect-configs
    config.storage.replication.factor=1
    offset.storage.topic=_connect-offsets
    offset.storage.replication.factor=1
    offset.storage.partitions=1
    status.storage.topic=_connect-status
    status.storage.replication.factor=1
    status.storage.partitions=1

    key.converter=org.apache.kafka.connect.storage.StringConverter
    value.converter=org.apache.kafka.connect.json.JsonConverter
    value.converter.schemas.enable=false

    rest.port=8083
    plugin.path=/opt/kafka/connect-plugins
  EOF
}

module "kafka_connect_task_definition" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name                 = "${var.name}-kafka-connect"
  cluster_arn          = var.ecs_cluster_arn
  force_new_deployment = true

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

  enable_execute_command = true

  volume = {
    "connect-config" = {}
  }

  container_definitions = {
    config-writer = {
      cpu                    = 0
      memory                 = 128
      essential              = false
      image                  = "public.ecr.aws/docker/library/busybox:1.36.1"
      user                   = "0"
      readonlyRootFilesystem = false
      entrypoint             = ["/bin/sh", "-ec"]
      command = [<<-EOT
        cat <<'EOF' >/etc/kafka-connect/connect-distributed.properties
        ${local.connect_distributed_properties}
        EOF
      EOT
      ]

      mountPoints = [
        {
          sourceVolume  = "connect-config"
          containerPath = "/etc/kafka-connect"
          readOnly      = false
        }
      ]

      enable_cloudwatch_logging = true
    }

    kafka-connect = {
      cpu                    = var.cpu
      memory                 = var.memory - 128
      essential              = true
      image                  = var.image_uri
      user                   = "0"
      readonlyRootFilesystem = false

      dependsOn = [
        {
          containerName = "config-writer"
          condition     = "SUCCESS"
        }
      ]

      environment = [
        {
          name  = "KAFKA_HEAP_OPTS"
          value = "-Xms128M -Xmx512M"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "connect-config"
          containerPath = "/etc/kafka-connect"
          readOnly      = true
        }
      ]

      portMappings = [
        {
          name          = "kafka-connect-rest"
          containerPort = 8083
          hostPort      = 8083
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
        port_name      = "kafka-connect-rest"
        discovery_name = "kafka-connect-sc"
        client_alias = {
          dns_name = "kafka-connect"
          port     = 8083
        }
      }
    ]
  }

  security_group_ingress_rules = {}

  security_group_egress_rules = {
    all = {
      type        = "egress"
      from_port   = 0
      to_port     = 65535
      protocol    = "-1"
      description = "Allow traffic anywhere (Kafka broker + OpenSearch domain, both in-VPC)"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  create_task_exec_iam_role = true
  task_exec_iam_role_name   = "${var.name}-kafka-connect-exec"
  task_exec_iam_role_policies = {
    exec_policy = var.task_exec_policy_arn
  }

  tasks_iam_role_statements = [
    {
      sid    = "OpenSearchSigV4Access"
      effect = "Allow"
      actions = [
        "es:ESHttpGet",
        "es:ESHttpPut",
        "es:ESHttpPost",
        "es:ESHttpDelete",
        "es:ESHttpHead"
      ]
      resources = ["${var.opensearch_domain_arn}/*"]
    }
  ]

  tags = var.tags
}
