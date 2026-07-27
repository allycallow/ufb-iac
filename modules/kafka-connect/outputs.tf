output "security_group_id" {
  description = "Security group ID of the Kafka Connect ECS service"
  value       = module.kafka_connect_task_definition.security_group_id
}
