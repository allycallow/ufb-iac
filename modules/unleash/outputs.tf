output "security_group_id" {
  value = module.unleash.security_group_id
}

output "service_name" {
  value = module.unleash.name
}

output "db_secret_arn" {
  description = "Secrets Manager secret holding the dedicated Unleash PostgreSQL user credentials (username: unleash). Not auto-rotated. Run the db-bootstrap task (see the other db_bootstrap_* outputs and README.md) to create or update the matching Postgres role/database."
  value       = aws_secretsmanager_secret.db.arn
}

# ── DB-bootstrap one-off task, consumed by the deployment runbook ────────────

output "db_bootstrap_task_definition_family" {
  description = "Run with `aws ecs run-task` before the first service start, and again after manually rotating db_secret_arn."
  value       = aws_ecs_task_definition.db_bootstrap.family
}

output "db_bootstrap_task_definition_arn" {
  value = aws_ecs_task_definition.db_bootstrap.arn
}

output "db_bootstrap_security_group_id" {
  value = aws_security_group.db_bootstrap.id
}

output "run_task_network_configuration" {
  description = "Ready-made --network-configuration argument for the db-bootstrap one-off task."
  value       = "awsvpcConfiguration={subnets=[${join(",", var.private_subnets)}],securityGroups=[${aws_security_group.db_bootstrap.id}],assignPublicIp=DISABLED}"
}
