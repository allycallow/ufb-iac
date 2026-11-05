# Self-hosted stand-in for the managed OpenSearch domain (see
# modules/search's `manage_opensearch` toggle), used pre-launch to cut cost
# while there's no real traffic. Security plugin disabled - this is only
# reachable from inside the VPC via Service Connect, never public - so
# existing IAM-signed/TLS-verifying clients (ufb-search, the Airflow
# reindex_opensearch DAG, the kafka-connect sink) don't need AWS-specific
# auth or a trusted cert here; see OPENSEARCH_MANAGED in those app repos.
#
# No persistent volume: unlike the managed domain, this index is fully
# rebuildable from Postgres via Airflow's reindex_opensearch DAG, so losing
# it on a restart is an accepted tradeoff - same call already made for
# Kafka's EBS volume on scale-to-zero.
module "opensearch_task_definition" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name                 = "${var.name}-opensearch"
  cluster_arn          = var.ecs_cluster_arn
  force_new_deployment = true

  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  cpu    = 1024
  memory = 2048

  # Brand new service with no real-world state to protect (see
  # modules/radio/ecs.tf for the same reasoning) - just start at zero.
  # Bump to 1 before a test session, back to 0 after.
  desired_count      = 0
  enable_autoscaling = false

  container_definitions = {
    opensearch = {
      cpu       = 1024
      memory    = 2048
      essential = true
      image     = "opensearchproject/opensearch:2.19.0"
      # Unlike most other containers in this repo, NOT root - the official
      # image refuses to start as root ("OpenSearch cannot run as root.
      # Please start your container as another user."), exiting 1
      # immediately. Runs as its own baked-in non-root user instead.
      readonlyRootFilesystem                 = false
      cloudwatch_log_group_retention_in_days = 1

      environment = [
        {
          name  = "discovery.type"
          value = "single-node"
        },
        {
          name  = "DISABLE_SECURITY_PLUGIN"
          value = "true"
        },
        {
          name  = "OPENSEARCH_JAVA_OPTS"
          value = "-Xms512m -Xmx512m"
        }
      ]

      portMappings = [
        {
          name          = "opensearch"
          containerPort = 9200
          hostPort      = 9200
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
      port_name      = "opensearch"
      discovery_name = "opensearch-sc"
      client_alias = {
        dns_name = "opensearch"
        port     = 9200
      }
    }]
  }

  security_group_ingress_rules = {
    for idx, sg_id in var.client_security_group_ids : "client_${idx}_opensearch" => {
      type                         = "ingress"
      from_port                    = 9200
      to_port                      = 9200
      protocol                     = "tcp"
      description                  = "Allow OpenSearch traffic from client service"
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
  task_exec_iam_role_name   = "${var.name}-opensearch-exec"
  task_exec_iam_role_policies = {
    exec_policy = var.task_exec_policy_arn
  }

  tags = var.tags
}
