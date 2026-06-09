output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  value = module.vpc.vpc_cidr_block
}

output "public_subnets" {
  value = module.vpc.public_subnets
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "database_subnet_group" {
  value = module.vpc.database_subnet_group
}

output "elasticache_subnet_group" {
  value = module.vpc.elasticache_subnet_group
}

output "private_route_table_ids" {
  value = module.vpc.private_route_table_ids
}

output "rds_sg_id" {
  value = module.security_group_rds.security_group_id
}

output "redis_sg_id" {
  value = module.security_group_redis.security_group_id
}

output "vpc_lambda_sg_id" {
  value = module.security_group_vpc_lambda.security_group_id
}
