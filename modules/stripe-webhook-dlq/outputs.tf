output "dlq_arns" {
  description = "Map of handler name to DLQ ARN"
  value       = { for name, q in aws_sqs_queue.dlq : name => q.arn }
}

output "dlq_urls" {
  description = "Map of handler name to DLQ URL"
  value       = { for name, q in aws_sqs_queue.dlq : name => q.url }
}
