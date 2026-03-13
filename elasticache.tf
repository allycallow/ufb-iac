resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${local.name}-app"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.1"
  port                 = 6379
  security_group_ids   = [module.security_group_redis.security_group_id]
  subnet_group_name    = module.vpc.elasticache_subnet_group
}

output "redis_endpoint" {
  value = "${aws_elasticache_cluster.redis.cache_nodes[0].address}:${aws_elasticache_cluster.redis.cache_nodes[0].port}"
}
