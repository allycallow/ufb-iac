output "security_group_id" {
  value = module.redis_task_definition.security_group_id
}

output "host" {
  description = "Service Connect short name, resolvable by any task in a Service-Connect-enabled service (same pattern as modules/kafka's `kafka` alias)."
  value       = "redis"
}
