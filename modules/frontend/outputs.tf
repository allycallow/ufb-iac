output "security_group_id" {
  description = "Security group ID of the frontend ECS service"
  value       = module.frontend_task_definition.security_group_id
}
