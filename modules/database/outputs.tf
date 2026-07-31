output "db_instance_endpoint" {
  value = module.db.db_instance_endpoint
}

output "db_instance_identifier" {
  value = module.db.db_instance_identifier
}

output "db_instance_resource_id" {
  value = module.db.db_instance_resource_id
}

output "db_instance_host" {
  description = "Endpoint with the :port suffix stripped, for consumers that need a bare hostname."
  value       = split(":", module.db.db_instance_endpoint)[0]
}

output "db_instance_master_user_secret_arn" {
  description = "RDS-managed master credentials secret (manage_master_user_password defaults to true)."
  value       = module.db.db_instance_master_user_secret_arn
}

output "redis_host" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_endpoint" {
  value = "${aws_elasticache_replication_group.redis.primary_endpoint_address}:${aws_elasticache_replication_group.redis.port}"
}

output "redis_replication_group_id" {
  value = aws_elasticache_replication_group.redis.replication_group_id
}

output "s3_export_policy_arn" {
  value = aws_iam_policy.s3_export_policy.arn
}
