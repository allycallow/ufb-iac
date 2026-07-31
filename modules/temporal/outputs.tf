# ── Client-facing addresses ───────────────────────────────────────────────────

output "frontend_address" {
  description = "gRPC address for Temporal clients and workers, e.g. temporal-frontend.production-ufb.internal:7233"
  value       = local.frontend_address
}

output "frontend_host" {
  description = "Cloud Map DNS name of the frontend, without the port."
  value       = local.frontend_host
}

output "frontend_grpc_port" {
  value = local.frontend_grpc_port
}

output "namespace" {
  description = "Namespace registered by the admin bootstrap task."
  value       = var.temporal_default_namespace
}

output "task_queue" {
  description = "Task queue the Python worker polls."
  value       = var.worker_task_queue
}

# ── Web UI ────────────────────────────────────────────────────────────────────

output "ui_url" {
  description = <<-EOT
    Internal-only URL for the Temporal Web UI. Falls back to the Cloud Map
    address when create_ui_alb is false — resolvable inside the VPC only.
  EOT
  value = var.create_ui_alb ? (
    "${var.ui_certificate_arn == null ? "http" : "https"}://${module.alb[0].dns_name}:${var.ui_port}"
  ) : "http://temporal-ui.${var.service_discovery_namespace_name}:${var.ui_port}"
}

output "ui_alb_dns_name" {
  description = "Null when create_ui_alb is false."
  value       = try(module.alb[0].dns_name, null)
}

output "ui_alb_zone_id" {
  description = "For an optional Route 53 alias record pointing at the internal ALB. Null when there is no ALB."
  value       = try(module.alb[0].zone_id, null)
}

# ── Security groups, for other services that need to talk to Temporal ─────────

output "server_security_group_id" {
  value = aws_security_group.server.id
}

output "worker_security_group_id" {
  value = aws_security_group.worker.id
}

output "ui_security_group_id" {
  value = aws_security_group.ui.id
}

output "ui_alb_security_group_id" {
  description = "Null when create_ui_alb is false."
  value       = try(module.alb[0].security_group_id, null)
}

output "deployment_mode" {
  description = "Whether the server runs as one all-in-one task or one service per role."
  value       = var.deployment_mode
}

# ── One-off task definitions, consumed by the deployment runbook ──────────────

output "schema_task_definition_family" {
  description = "Run with `aws ecs run-task` before the first server start and before every server upgrade."
  value       = aws_ecs_task_definition.schema.family
}

output "schema_task_definition_arn" {
  value = aws_ecs_task_definition.schema.arn
}

output "admin_task_definition_family" {
  description = "Registers the default namespace; also the shell for ad-hoc temporal/tctl commands."
  value       = aws_ecs_task_definition.admin.family
}

output "admin_task_definition_arn" {
  value = aws_ecs_task_definition.admin.arn
}

output "schema_security_group_id" {
  description = "Pass to `aws ecs run-task --network-configuration` for the one-off tasks."
  value       = aws_security_group.schema.id
}

output "run_task_network_configuration" {
  description = "Ready-made --network-configuration argument for the one-off tasks."
  value       = "awsvpcConfiguration={subnets=[${join(",", var.private_subnets)}],securityGroups=[${aws_security_group.schema.id}],assignPublicIp=DISABLED}"
}

# ── Databases ─────────────────────────────────────────────────────────────────

output "temporal_database_name" {
  value = var.temporal_db_name
}

output "temporal_visibility_database_name" {
  value = var.temporal_visibility_db_name
}

# ── ECS service names, for deploys and alarms ─────────────────────────────────

output "server_service_names" {
  value = { for k, s in aws_ecs_service.server : k => s.name }
}

output "worker_service_name" {
  value = module.worker.name
}

output "ui_service_name" {
  value = module.ui.name
}
