output "db_instance_endpoint" {
  value = module.db.db_instance_endpoint
}

output "db_instance_identifier" {
  value = module.db.db_instance_identifier
}

output "redis_host" {
  value = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_endpoint" {
  value = "${aws_elasticache_cluster.redis.cache_nodes[0].address}:${aws_elasticache_cluster.redis.cache_nodes[0].port}"
}

output "s3_export_policy_arn" {
  value = aws_iam_policy.s3_export_policy.arn
}
