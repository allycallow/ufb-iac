output "security_group_id" {
  description = "Security group ID of the Kafka ECS service"
  value       = module.kafka_task_definition.security_group_id
}

output "broker_endpoint" {
  description = "Internal Service Connect address other ECS services use to reach the broker"
  value       = "kafka:9092"
}

output "broker_dns_endpoint" {
  description = "Plain Cloud Map DNS address for the broker. Unlike broker_endpoint's bare `kafka` short name (only resolvable by tasks with a Service Connect proxy), this FQDN resolves through normal VPC DNS — use it for standalone RunTask tasks."
  value       = "${aws_service_discovery_service.kafka.name}.${var.service_connect_namespace}:9092"
}
