module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = local.name
  cidr = local.vpc_cidr

  azs                 = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
  public_subnets      = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets     = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 3)]
  database_subnets    = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 6)]
  elasticache_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 12)]

  enable_nat_gateway = true
  enable_vpn_gateway = false
  single_nat_gateway = true

  create_database_subnet_group = true
}


resource "aws_vpc_endpoint" "s3" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.eu-west-2.s3"
  vpc_endpoint_type   = "Gateway"
  route_table_ids     = module.vpc.private_route_table_ids
  private_dns_enabled = false
}

output "vpc_private_subnets" {
  value = join(",", module.vpc.private_subnets)
}
