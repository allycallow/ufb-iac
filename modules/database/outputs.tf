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

output "debezium_secret_arn" {
  description = "Secrets Manager secret holding the debezium replication user's credentials, for Kafka Connect's outbox CDC connector. The role itself must be created manually against Postgres (see plan) using this generated password."
  value       = aws_secretsmanager_secret.debezium.arn
}

output "temporal_db_secret_arn" {
  description = "Secrets Manager secret holding the dedicated Temporal PostgreSQL user credentials (username: temporal). Not auto-rotated — rotation is deliberate and paired with a Temporal redeployment. The role itself must be created manually: read the password from this secret, then run: CREATE USER temporal WITH PASSWORD '...'; GRANT ALL PRIVILEGES ON DATABASE temporal TO temporal; GRANT ALL PRIVILEGES ON DATABASE temporal_visibility TO temporal; and in each database: GRANT ALL ON SCHEMA public TO temporal; GRANT ALL ON ALL TABLES IN SCHEMA public TO temporal; GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO temporal; ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO temporal; ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO temporal;"
  value       = aws_secretsmanager_secret.temporal_db.arn
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
