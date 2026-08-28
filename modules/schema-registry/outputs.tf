output "registry_arn" {
  value = aws_glue_registry.outbox_events.arn
}

output "registry_name" {
  value = aws_glue_registry.outbox_events.registry_name
}

output "schema_arns" {
  description = "Map of aggregate_type to its Glue schema ARN"
  value       = { for k, s in aws_glue_schema.this : k => s.arn }
}
