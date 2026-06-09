module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.name
  cidr = var.vpc_cidr

  azs                 = var.azs
  public_subnets      = [for k, v in var.azs : cidrsubnet(var.vpc_cidr, 8, k)]
  private_subnets     = [for k, v in var.azs : cidrsubnet(var.vpc_cidr, 8, k + 3)]
  database_subnets    = [for k, v in var.azs : cidrsubnet(var.vpc_cidr, 8, k + 6)]
  elasticache_subnets = [for k, v in var.azs : cidrsubnet(var.vpc_cidr, 8, k + 12)]

  enable_nat_gateway   = true
  enable_vpn_gateway   = false
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  create_database_subnet_group = true
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.eu-west-2.dynamodb"
  vpc_endpoint_type   = "Gateway"
  route_table_ids     = module.vpc.private_route_table_ids
  private_dns_enabled = false
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.eu-west-2.s3"
  vpc_endpoint_type   = "Gateway"
  route_table_ids     = module.vpc.private_route_table_ids
  private_dns_enabled = false
}

module "security_group_rds" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.name}-rds"
  description = "PostgreSQL security group"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "PostgreSQL access from within VPC"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Export to s3",
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}

module "security_group_vpc_lambda" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.name}-vpc-lambda"
  description = "Lambda in VPC security group"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 65535
      protocol    = "tcp"
      description = "",
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 65535
      protocol    = "tcp"
      description = "",
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}

module "security_group_redis" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.name}-redis"
  description = "Redis security group"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 6379
      to_port     = 6379
      protocol    = "tcp"
      description = "Redis access from within VPC"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
  ]

  egress_with_cidr_blocks = [
    {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "All Traffic"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}
