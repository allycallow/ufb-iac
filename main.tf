data "aws_ssoadmin_instances" "this" {}

terraform {
  required_version = "~> v1.12.2"

  backend "s3" {
    bucket = "ufb-terraform-state"
    key    = "terraform_state/terraform.tfstate"
    region = "eu-west-2"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.21.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5.0"
    }
  }
}

provider "aws" {
  default_tags {
    tags = {
      Environment = terraform.workspace
      Name        = local.name
    }
  }
}

locals {
  name              = "${terraform.workspace}-ufb"
  region            = "eu-west-2"
  domain            = "upfrontbeats.com"
  vpc_cidr          = "10.0.0.0/16"
  azs               = slice(data.aws_availability_zones.available.names, 0, 3)
  secret_prefix     = "arn:aws:secretsmanager:${local.region}:${data.aws_caller_identity.current.account_id}:secret:prod/ufb/backend-NKRahZ"
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
}

# ── Infrastructure Modules ────────────────────────────────────────────────────

module "networking" {
  source   = "./modules/networking"
  name     = local.name
  vpc_cidr = local.vpc_cidr
  azs      = local.azs
}

module "container_registry" {
  source = "./modules/container-registry"
  name   = local.name
  repositories = [
    "backend",
    "frontend",
    "airflow",
    "audio-processing",
    "search",
    "track-metadata",
    "recommendations",
    "kafka-connect",
    "temporal-worker"
  ]
}

module "storage" {
  source               = "./modules/storage"
  name                 = local.name
  domain               = local.domain
  s3_media_bucket_name = var.s3_media_bucket_name
}

module "cdn" {
  source = "./modules/cdn"

  name                       = local.name
  domain                     = local.domain
  media_bucket_domain_name   = module.storage.media_bucket_domain_name
  media_bucket_id            = module.storage.media_bucket_id
  media_bucket_arn           = module.storage.media_bucket_arn
  frontend_bucket_id         = module.storage.frontend_bucket_id
  frontend_bucket_arn        = module.storage.frontend_bucket_arn
  alb_dns_name               = module.alb.dns_name
  media_public_key_pem       = tls_private_key.media.public_key_pem
  preview_public_key_pem     = tls_private_key.preview_media.public_key_pem
  viewer_response_lambda_arn = var.viewer_response_lambda_arn
  viewer_request_lambda_arn  = var.viewer_request_lambda_arn
  origin_response_lambda_arn = var.origin_response_lambda_arn
}

module "auth" {
  source = "./modules/auth"

  name                 = local.name
  domain               = local.domain
  account_id           = data.aws_caller_identity.current.account_id
  google_client_id     = var.google_client_id
  google_client_secret = var.google_client_secret
  apple_client_id      = var.apple_client_id
  apple_team_id        = var.apple_team_id
  apple_key_id         = var.apple_key_id
  apple_private_key    = var.apple_private_key
}

module "ecs_cluster" {
  source = "./modules/ecs-cluster"

  name          = local.name
  region        = local.region
  account_id    = data.aws_caller_identity.current.account_id
  vpc_id        = module.networking.vpc_id
  secret_prefix = local.secret_prefix
}

module "database" {
  source = "./modules/database"

  name                     = local.name
  database_subnet_group    = module.networking.database_subnet_group
  rds_sg_id                = module.networking.rds_sg_id
  elasticache_sg_id        = module.networking.redis_sg_id
  elasticache_subnet_group = module.networking.elasticache_subnet_group
}

module "email" {
  source  = "./modules/email"
  domain  = local.domain
  zone_id = data.aws_route53_zone.main.zone_id
}

# ── Service Modules ───────────────────────────────────────────────────────────

module "audio_processing" {
  source = "./modules/audio-processing"

  name = "${local.name}-audio-processing"

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "audio-processing"
  }

  media_bucket_arn          = module.storage.media_bucket_arn
  media_bucket_id           = module.storage.media_bucket_id
  ecs_cluster_arn           = module.ecs_cluster.cluster_arn
  image_uri                 = "${module.container_registry.repository_urls["audio-processing"]}:latest"
  private_subnets           = module.networking.private_subnets
  event_bus_arn             = module.eventbridge.eventbridge_bus_arn
  service_connect_namespace = module.ecs_cluster.service_discovery_namespace_name
}

module "search" {
  source = "./modules/search"

  name = "${local.name}-search"

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "search"
  }

  ecs_cluster_arn           = module.ecs_cluster.cluster_arn
  image_uri                 = "${module.container_registry.repository_urls["search"]}:latest"
  alb_security_group_id     = module.alb.security_group_id
  backend_security_group_id = module.backend.security_group_id
  service_connect_namespace = module.ecs_cluster.service_discovery_namespace_name
  private_subnets           = module.networking.private_subnets
  alb_target_group_arn      = module.alb.target_groups["search"].arn
  vpc_id                    = module.networking.vpc_id
  vpc_cidr_block            = module.networking.vpc_cidr_block

  teleport_security_group_id   = module.teleport.security_group_id
  monitoring_security_group_id = module.monitoring.security_group_id
}

module "kafka" {
  source = "./modules/kafka"

  name = local.name

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "kafka"
  }

  vpc_id                    = module.networking.vpc_id
  private_subnets           = module.networking.private_subnets
  ecs_cluster_arn           = module.ecs_cluster.cluster_arn
  service_connect_namespace = module.ecs_cluster.service_discovery_namespace_name
  task_exec_policy_arn      = module.ecs_cluster.task_exec_policy_arn

  client_security_group_ids = [
    module.backend.security_group_id,
    module.kafka_connect.security_group_id,
    module.temporal.worker_security_group_id,
    module.audio_processing.security_group_id,
    module.track_metadata_processing.security_group_id,
  ]

  metrics_client_security_group_ids = [
    module.monitoring.security_group_id,
  ]
}

module "kafka_connect" {
  source = "./modules/kafka-connect"

  name = local.name

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "kafka-connect"
  }

  vpc_id                    = module.networking.vpc_id
  private_subnets           = module.networking.private_subnets
  ecs_cluster_arn           = module.ecs_cluster.cluster_arn
  service_connect_namespace = module.ecs_cluster.service_discovery_namespace_name
  task_exec_policy_arn      = module.ecs_cluster.task_exec_policy_arn
  image_uri                 = "${module.container_registry.repository_urls["kafka-connect"]}:latest"
  opensearch_domain_arn     = module.search.opensearch_domain_arn
  audio_upload_queue_arn    = module.audio_processing.queue_arn
  debezium_secret_arn       = module.database.debezium_secret_arn
  db_host                   = module.database.db_instance_host
  db_name                   = "ufb"
}

module "teleport" {
  source = "./modules/teleport"

  name       = local.name
  region     = local.region
  account_id = data.aws_caller_identity.current.account_id

  vpc_id          = module.networking.vpc_id
  public_subnets  = module.networking.public_subnets
  private_subnets = module.networking.private_subnets

  ecs_cluster_arn           = module.ecs_cluster.cluster_arn
  task_exec_policy_arn      = module.ecs_cluster.task_exec_policy_arn
  service_connect_namespace = module.ecs_cluster.service_discovery_namespace_name

  zone_id    = data.aws_route53_zone.main.zone_id
  acme_email = var.acme_email

  db_instance_endpoint    = module.database.db_instance_endpoint
  db_instance_identifier  = module.database.db_instance_identifier
  db_instance_resource_id = module.database.db_instance_resource_id

  redis_endpoint             = module.database.redis_endpoint
  redis_replication_group_id = module.database.redis_replication_group_id

  opensearch_domain_endpoint = module.search.opensearch_domain_endpoint
  opensearch_domain_arn      = module.search.opensearch_domain_arn

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "teleport"
  }
}

module "track_metadata_processing" {
  source = "./modules/track-metadata"

  name = "${local.name}-tm-processing"

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "tm-processing"
  }

  media_bucket_arn          = module.storage.media_bucket_arn
  media_bucket_id           = module.storage.media_bucket_id
  ecs_cluster_arn           = module.ecs_cluster.cluster_arn
  image_uri                 = "${module.container_registry.repository_urls["track-metadata"]}:latest"
  private_subnets           = module.networking.private_subnets
  service_connect_namespace = module.ecs_cluster.service_discovery_namespace_name
}

module "recommendations" {
  source = "./modules/recommendations"

  name = "${local.name}-recommendations"

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "recommendations"
  }

  ecs_cluster_arn           = module.ecs_cluster.cluster_arn
  image_uri                 = "${module.container_registry.repository_urls["recommendations"]}:latest"
  alb_security_group_id     = module.alb.security_group_id
  backend_security_group_id = module.backend.security_group_id
  service_connect_namespace = module.ecs_cluster.service_discovery_namespace_name
  private_subnets           = module.networking.private_subnets
  alb_target_group_arn      = module.alb.target_groups["recommendations"].arn

  teleport_security_group_id   = module.teleport.security_group_id
  monitoring_security_group_id = module.monitoring.security_group_id
}

module "recently-played" {
  source = "./modules/recently-played"
  name   = "${local.name}-recently-played"

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "recently-played"
  }
}

module "idempotency" {
  source = "./modules/idempotency"
  stage  = terraform.workspace

  tags = {
    Environment = terraform.workspace
    Name        = local.name
  }
}

module "monitoring" {
  source = "./modules/monitoring"

  name = "${local.name}-monitoring"

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "monitoring"
  }

  ecs_cluster_arn           = module.ecs_cluster.cluster_arn
  alb_security_group_id     = module.alb.security_group_id
  private_subnets           = module.networking.private_subnets
  alb_target_group_arn      = module.alb.target_groups["monitoring"].arn
  vpc_cidr_block            = module.networking.vpc_cidr_block
  vpc_id                    = module.networking.vpc_id
  service_connect_namespace = module.ecs_cluster.service_discovery_namespace_name

  # Redpanda's admin API, aliased over Service Connect (modules/kafka/ecs.tf).
  kafka_admin_target = "kafka:9644"

  # The Temporal server's Cloud Map A record (not Service Connect — see
  # modules/temporal/main.tf). Hardcoded rather than wired through
  # module.temporal's output to avoid a module dependency cycle: module.temporal
  # already depends on module.monitoring.security_group_id above. One entry per
  # role in multi-role mode ("temporal-frontend", "temporal-history",
  # "temporal-matching", "temporal-internal-worker") — update this list if
  # module.temporal's deployment_mode ever changes from single-node.
  temporal_metrics_targets = [
    "temporal-frontend.${module.ecs_cluster.service_discovery_namespace_name}:9090",
  ]
}

module "frontend" {
  source = "./modules/frontend"

  name = "${local.name}-frontend"

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "frontend"
  }

  ecs_cluster_arn           = module.ecs_cluster.cluster_arn
  image_uri                 = "${module.container_registry.repository_urls["frontend"]}:latest"
  alb_security_group_id     = module.alb.security_group_id
  private_subnets           = module.networking.private_subnets
  alb_target_group_arn      = module.alb.target_groups["frontend"].arn
  service_connect_namespace = module.ecs_cluster.service_discovery_namespace_name
  task_exec_policy_arn      = module.ecs_cluster.task_exec_policy_arn
}

module "backend" {
  source = "./modules/backend"

  name = "${local.name}-backend"

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "backend"
  }

  ecs_cluster_arn              = module.ecs_cluster.cluster_arn
  image_uri                    = "${module.container_registry.repository_urls["backend"]}:latest"
  alb_security_group_id        = module.alb.security_group_id
  monitoring_security_group_id = module.monitoring.security_group_id
  frontend_security_group_id   = module.frontend.security_group_id
  private_subnets              = module.networking.private_subnets
  alb_target_group_arn         = module.alb.target_groups["backend"].arn
  service_connect_namespace    = module.ecs_cluster.service_discovery_namespace_name
  db_endpoint                  = split(":", module.database.db_instance_endpoint)[0]
  media_bucket_name            = module.storage.media_bucket_name
  media_bucket_arn             = module.storage.media_bucket_arn
  cognito_user_pool_id         = module.auth.user_pool_id
  cognito_app_client_id        = module.auth.user_pool_web_client_id
  cognito_user_pool_arn        = module.auth.user_pool_arn
  cf_media_key_id              = module.cdn.cf_media_key_id
  cf_preview_key_id            = module.cdn.cf_preview_key_id
  event_bus_name               = module.eventbridge.eventbridge_bus_name
  event_bus_arn                = module.eventbridge.eventbridge_bus_arn
  redis_host                   = module.database.redis_host
  secret_prefix                = local.secret_prefix
  task_exec_policy_arn         = module.ecs_cluster.task_exec_policy_arn
}

module "temporal" {
  source = "./modules/temporal"

  name       = "${local.name}-temporal"
  region     = local.region
  account_id = data.aws_caller_identity.current.account_id

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "temporal"
  }

  # Reuses the shared VPC, ECS cluster, Cloud Map namespace and ECR registry.
  vpc_id          = module.networking.vpc_id
  vpc_cidr_block  = module.networking.vpc_cidr_block
  private_subnets = module.networking.private_subnets

  ecs_cluster_arn                  = module.ecs_cluster.cluster_arn
  task_exec_policy_arn             = module.ecs_cluster.task_exec_policy_arn
  service_discovery_namespace_id   = module.ecs_cluster.service_discovery_namespace_id
  service_discovery_namespace_name = module.ecs_cluster.service_discovery_namespace_name

  worker_image_uri = "${module.container_registry.repository_urls["temporal-worker"]}:latest"

  # Persistence lives on the existing RDS PostgreSQL instance, in its own
  # `temporal` and `temporal_visibility` databases created by the schema task.
  db_host       = module.database.db_instance_host
  db_secret_arn = module.database.db_instance_master_user_secret_arn

  # Services allowed to start workflows against the frontend on 7233.
  client_security_group_ids = [
    module.backend.security_group_id,
    module.airflow.security_group_id,
    module.teleport.security_group_id,
  ]

  # Who may reach the Web UI.
  ui_client_security_group_ids = [
    module.teleport.security_group_id,
    module.monitoring.security_group_id,
  ]

  # Let Prometheus scrape the server's built-in metrics endpoint.
  metrics_client_security_group_ids = [
    module.monitoring.security_group_id,
  ]

  # TrackIngestionSagaWorkflow's trigger topic, and the ECS RunTask activities
  # it drives — audio-processing and track-metadata, invoked the same way
  # Airflow's EcsRunTaskOperator used to.
  worker_environment = {
    KAFKA_BOOTSTRAP_SERVERS             = "kafka:9092"
    KAFKA_AUDIO_UPLOADS_TOPIC           = "ufb.audio_uploads"
    KAFKA_TRACK_PROCESSING_EVENTS_TOPIC = "ufb.track_processing_events"

    BACKEND_ENDPOINT = "https://new-admin.upfrontbeats.com"

    ECS_CLUSTER = module.ecs_cluster.cluster_name
    ECS_SUBNETS = join(",", module.networking.private_subnets)

    AUDIO_PROCESSING_TASK_DEFINITION = module.audio_processing.task_definition_family
    AUDIO_PROCESSING_CONTAINER_NAME  = "audio-processing"
    AUDIO_PROCESSING_SECURITY_GROUP  = module.audio_processing.security_group_id

    TRACK_METADATA_TASK_DEFINITION = module.track_metadata_processing.task_definition_family
    TRACK_METADATA_CONTAINER_NAME  = "tm-processing"
    TRACK_METADATA_SECURITY_GROUP  = module.track_metadata_processing.security_group_id
  }

  worker_secrets = {
    BACKEND_API_KEY = "${local.secret_prefix}:API_KEY::"
  }
  worker_secret_arns = [local.secret_prefix]

  worker_task_role_statements = [
    {
      sid    = "RunAudioPipelineTasks"
      effect = "Allow"
      actions = [
        "ecs:RunTask",
        "ecs:DescribeTasks",
      ]
      resources = [
        "arn:aws:ecs:${local.region}:${data.aws_caller_identity.current.account_id}:task-definition/${module.audio_processing.task_definition_family}:*",
        "arn:aws:ecs:${local.region}:${data.aws_caller_identity.current.account_id}:task-definition/${module.track_metadata_processing.task_definition_family}:*",
        "arn:aws:ecs:${local.region}:${data.aws_caller_identity.current.account_id}:task/${module.ecs_cluster.cluster_name}/*",
      ]
    },
    {
      sid     = "PassAudioPipelineTaskRoles"
      effect  = "Allow"
      actions = ["iam:PassRole"]
      resources = [
        module.audio_processing.task_role_arn,
        module.audio_processing.task_exec_role_arn,
        module.track_metadata_processing.task_role_arn,
        module.track_metadata_processing.task_exec_role_arn,
      ]
      condition = [{
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["ecs-tasks.amazonaws.com"]
      }]
    },
  ]

  # ── Cost profile: ~$33/month in eu-west-2, vs ~$260 for the HA topology ──────
  #
  # Every setting below trades availability or headroom for cost. To move to the
  # production topology, delete this block: the module defaults are the HA ones,
  # and switching back needs no database change.

  # All four roles in one task instead of one service each — the single biggest
  # saving (~$170/mo). Deploys still roll (ECS starts the replacement before
  # draining the old task), but an unplanned task loss means Temporal is
  # unavailable for the minute or two ECS takes to replace it. Workflow state
  # lives in RDS, so nothing is lost — execution pauses and resumes.
  deployment_mode    = "single-node"
  single_node_cpu    = 512
  single_node_memory = 1024

  # 128 rather than 512 shards. IMMUTABLE — changing it later requires a fresh
  # database and loses all workflow history. 128 keeps idle CPU and idle RDS
  # write load low while leaving room to grow into real production volume.
  temporal_num_history_shards = 128

  # No internal ALB (~$19/mo). The UI is still deployed and registered in Cloud
  # Map as temporal-ui.production-ufb.internal:8080 — reach it through the
  # existing Teleport application access.
  create_ui_alb    = false
  ui_desired_count = 1

  # One worker, effectively all on Spot. Interruption is safe: the worker stops
  # polling and Temporal redelivers its tasks.
  #
  # The weights must be set alongside base = 0. The module defaults are 4:1
  # spot:on-demand, which with base = 0 puts 1 task in 5 on on-demand — and with
  # a single task that means a ~20% chance of paying full price for it. 99:1
  # keeps on-demand available purely as a fallback when a Spot pool is exhausted.
  worker_desired_count    = 1
  worker_min_capacity     = 1
  worker_max_capacity     = 4
  worker_on_demand_base   = 0
  worker_spot_weight      = 99
  worker_on_demand_weight = 1

  # Trim log spend.
  temporal_log_level = "warn"
  log_retention_days = 7
}

module "airflow" {
  source = "./modules/airflow"

  name = "${local.name}-airflow"

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "airflow"
  }

  ecs_cluster_arn              = module.ecs_cluster.cluster_arn
  image_uri                    = "${module.container_registry.repository_urls["airflow"]}:latest"
  alb_security_group_id        = module.alb.security_group_id
  monitoring_security_group_id = module.monitoring.security_group_id
  private_subnets              = module.networking.private_subnets
  alb_target_group_arn         = module.alb.target_groups["airflow"].arn
  service_connect_namespace    = module.ecs_cluster.service_discovery_namespace_name
  task_exec_policy_arn         = module.ecs_cluster.task_exec_policy_arn

  # ~$78/month on-demand -> ~$23 on Spot. Single task on LocalExecutor, so a
  # reclaim interrupts in-flight DAG tasks and drops the UI for 1-2 minutes.
  use_spot = true
}
