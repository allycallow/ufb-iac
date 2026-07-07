output "db_instance_endpoint" {
  value = module.db.db_instance_endpoint
}

output "db_instance_identifier" {
  value = module.db.db_instance_identifier
}

output "db_instance_resource_id" {
  value = module.db.db_instance_resource_id
}

output "redis_host" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_endpoint" {
  value = "${aws_elasticache_replication_group.redis.primary_endpoint_address}:${aws_elasticache_replication_group.redis.port}"
}

output "s3_export_policy_arn" {
  value = aws_iam_policy.s3_export_policy.arn
}
