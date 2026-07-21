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
    "recommendations"
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

  name                      = local.name
  region                    = local.region
  account_id                = data.aws_caller_identity.current.account_id
  vpc_id                      = module.networking.vpc_id
  ssm_media_private_key_arn   = aws_ssm_parameter.media_private_key.arn
  ssm_preview_private_key_arn = aws_ssm_parameter.preview_media_private_key.arn
  secret_prefix               = local.secret_prefix
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

  media_bucket_arn = module.storage.media_bucket_arn
  media_bucket_id  = module.storage.media_bucket_id
  ecs_cluster_arn  = module.ecs_cluster.cluster_arn
  image_uri        = "${module.container_registry.repository_urls["audio-processing"]}:latest"
  private_subnets  = module.networking.private_subnets
  event_bus_arn    = module.eventbridge.eventbridge_bus_arn
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
  event_bus_name            = module.eventbridge.eventbridge_bus_arn

  teleport_security_group_id   = module.teleport.security_group_id
  monitoring_security_group_id = module.monitoring.security_group_id
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

  media_bucket_arn = module.storage.media_bucket_arn
  media_bucket_id  = module.storage.media_bucket_id
  ecs_cluster_arn  = module.ecs_cluster.cluster_arn
  image_uri        = "${module.container_registry.repository_urls["track-metadata"]}:latest"
  private_subnets  = module.networking.private_subnets
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
  media_private_key_arn        = aws_ssm_parameter.media_private_key.arn
  preview_private_key_arn      = aws_ssm_parameter.preview_media_private_key.arn
  secret_prefix                = local.secret_prefix
  task_exec_policy_arn         = module.ecs_cluster.task_exec_policy_arn
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
  audio_processing_queue_arn   = module.audio_processing.queue_arn
  audio_processing_dlq_arn     = module.audio_processing.dlq_arn
  task_exec_policy_arn         = module.ecs_cluster.task_exec_policy_arn
}
