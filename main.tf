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

  ecs_cluster_arn            = module.ecs_cluster.arn
  image_uri                  = "${aws_ecr_repository.repos["search"].repository_url}:latest"
  alb_security_group_id      = module.alb.security_group_id
  private_subnets            = module.vpc.private_subnets
  alb_target_group_arn       = module.alb.target_groups["search"].arn
  opensearch_domain_endpoint = aws_elasticsearch_domain.main.endpoint
}
