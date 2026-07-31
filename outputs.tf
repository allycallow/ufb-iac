# ── Temporal ──────────────────────────────────────────────────────────────────
# Consumed by the deployment runbook in modules/temporal/README.md.

output "temporal_frontend_address" {
  description = "gRPC address for Temporal clients and workers."
  value       = module.temporal.frontend_address
}

output "temporal_namespace" {
  value = module.temporal.namespace
}

output "temporal_task_queue" {
  value = module.temporal.task_queue
}

output "temporal_ui_url" {
  description = "Internal-only Temporal Web UI. Reachable from inside the VPC or over the VPN."
  value       = module.temporal.ui_url
}

output "temporal_schema_task_definition" {
  description = "Run before the first server start and before every server upgrade."
  value       = module.temporal.schema_task_definition_family
}

output "temporal_admin_task_definition" {
  description = "Registers the default namespace; also the shell for ad-hoc temporal/tctl commands."
  value       = module.temporal.admin_task_definition_family
}

output "temporal_run_task_network_configuration" {
  description = "Ready-made --network-configuration argument for `aws ecs run-task`."
  value       = module.temporal.run_task_network_configuration
}

output "temporal_worker_repository_url" {
  description = "ECR repository to push the Python worker image to."
  value       = module.container_registry.repository_urls["temporal-worker"]
}
