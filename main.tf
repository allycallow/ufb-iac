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

module "audio_processing" {
  source = "./modules/audio-processing"

  name = "${local.name}-audio-processing"

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "audio-processing"
  }

  media_bucket_arn = aws_s3_bucket.media.arn
  media_bucket_id  = aws_s3_bucket.media.id
  ecs_cluster_arn  = module.ecs_cluster.arn
  image_uri        = "${aws_ecr_repository.repos["audio-processing"].repository_url}:latest"
  private_subnets  = module.vpc.private_subnets
}


module "search" {
  source = "./modules/search"

  name = "${local.name}-search"

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "search"
  }

  ecs_cluster_arn           = module.ecs_cluster.arn
  image_uri                 = "${aws_ecr_repository.repos["search"].repository_url}:latest"
  alb_security_group_id     = module.alb.security_group_id
  backend_security_group_id = module.backend.security_group_id
  service_connect_namespace = aws_service_discovery_private_dns_namespace.ecs.name
  private_subnets           = module.vpc.private_subnets
  alb_target_group_arn      = module.alb.target_groups["search"].arn
  vpc_id                    = module.vpc.vpc_id
  vpc_cidr_block            = module.vpc.vpc_cidr_block
  event_bus_name            = module.eventbridge.eventbridge_bus_arn
}

module "track_metadata_processing" {
  source = "./modules/track-metadata"

  name = "${local.name}-tm-processing"

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "tm-processing"
  }

  media_bucket_arn = aws_s3_bucket.media.arn
  media_bucket_id  = aws_s3_bucket.media.id
  ecs_cluster_arn  = module.ecs_cluster.arn
  image_uri        = "${aws_ecr_repository.repos["track-metadata"].repository_url}:latest"
  private_subnets  = module.vpc.private_subnets
}

module "recommendations" {
  source = "./modules/recommendations"

  name = "${local.name}-recommendations"

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "recommendations"
  }

  ecs_cluster_arn           = module.ecs_cluster.arn
  image_uri                 = "${aws_ecr_repository.repos["recommendations"].repository_url}:latest"
  alb_security_group_id     = module.alb.security_group_id
  backend_security_group_id = module.backend.security_group_id
  service_connect_namespace = aws_service_discovery_private_dns_namespace.ecs.name
  private_subnets           = module.vpc.private_subnets
  alb_target_group_arn      = module.alb.target_groups["recommendations"].arn
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

module "monitoring" {
  source = "./modules/monitoring"

  name = "${local.name}-monitoring"

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "monitoring"
  }


  ecs_cluster_arn           = module.ecs_cluster.arn
  alb_security_group_id     = module.alb.security_group_id
  private_subnets           = module.vpc.private_subnets
  alb_target_group_arn      = module.alb.target_groups["monitoring"].arn
  vpc_cidr_block            = module.vpc.vpc_cidr_block
  vpc_id                    = module.vpc.vpc_id
  service_connect_namespace = aws_service_discovery_private_dns_namespace.ecs.name
}

module "frontend" {
  source = "./modules/frontend"

  name = "${local.name}-frontend"

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "frontend"
  }

  ecs_cluster_arn           = module.ecs_cluster.arn
  image_uri                 = "${aws_ecr_repository.repos["frontend"].repository_url}:latest"
  alb_security_group_id     = module.alb.security_group_id
  private_subnets           = module.vpc.private_subnets
  alb_target_group_arn      = module.alb.target_groups["frontend"].arn
  service_connect_namespace = aws_service_discovery_private_dns_namespace.ecs.name
  task_exec_policy_arn      = aws_iam_policy.ecs_task_exec_policy.arn
}

module "backend" {
  source = "./modules/backend"

  name = "${local.name}-backend"

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "backend"
  }

  ecs_cluster_arn              = module.ecs_cluster.arn
  image_uri                    = "${aws_ecr_repository.repos["backend"].repository_url}:latest"
  alb_security_group_id        = module.alb.security_group_id
  monitoring_security_group_id = module.monitoring.security_group_id
  frontend_security_group_id   = module.frontend.security_group_id
  private_subnets              = module.vpc.private_subnets
  alb_target_group_arn         = module.alb.target_groups["backend"].arn
  service_connect_namespace    = aws_service_discovery_private_dns_namespace.ecs.name
  db_endpoint                  = split(":", module.db.db_instance_endpoint)[0]
  media_bucket_name            = aws_s3_bucket.media.bucket
  media_bucket_arn             = aws_s3_bucket.media.arn
  cognito_user_pool_id         = aws_cognito_user_pool.pool.id
  cognito_app_client_id        = aws_cognito_user_pool_client.client.id
  cognito_user_pool_arn        = aws_cognito_user_pool.pool.arn
  cf_media_key_id              = aws_cloudfront_public_key.cf_media_key.id
  event_bus_name               = module.eventbridge.eventbridge_bus_name
  event_bus_arn                = module.eventbridge.eventbridge_bus_arn
  redis_host                   = aws_elasticache_cluster.redis.cache_nodes[0].address
  media_private_key_arn        = aws_ssm_parameter.media_private_key.arn
  secret_prefix                = local.secret_prefix
  task_exec_policy_arn         = aws_iam_policy.ecs_task_exec_policy.arn
}

module "airflow" {
  source = "./modules/airflow"

  name = "${local.name}-airflow"

  tags = {
    Environment = terraform.workspace
    Name        = local.name
    Workflow    = "airflow"
  }

  ecs_cluster_arn              = module.ecs_cluster.arn
  image_uri                    = "${aws_ecr_repository.repos["airflow"].repository_url}:latest"
  alb_security_group_id        = module.alb.security_group_id
  monitoring_security_group_id = module.monitoring.security_group_id
  private_subnets              = module.vpc.private_subnets
  alb_target_group_arn         = module.alb.target_groups["airflow"].arn
  service_connect_namespace    = aws_service_discovery_private_dns_namespace.ecs.name
  audio_processing_queue_arn   = module.audio_processing.queue_arn
  audio_processing_dlq_arn     = module.audio_processing.dlq_arn
  task_exec_policy_arn         = aws_iam_policy.ecs_task_exec_policy.arn
}
