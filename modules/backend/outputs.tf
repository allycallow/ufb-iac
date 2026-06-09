output "security_group_id" {
  description = "Security group ID of the backend ECS service"
  value       = module.backend_task_definition.security_group_id
}
