output "security_group_id" {
  description = "Security group ID of the Kafka ECS service"
  value       = module.kafka_task_definition.security_group_id
}

output "broker_endpoint" {
  description = "Internal Service Connect address other ECS services use to reach the broker"
  value       = "kafka:9092"
}
