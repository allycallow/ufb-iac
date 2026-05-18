output "security_group_id" {
  description = "Security group ID for the monitoring ECS service"
  value       = module.monitoring_service.security_group_id
}
