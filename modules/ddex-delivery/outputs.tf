output "bucket_id" {
  description = "ID of the DDEX deliveries bucket"
  value       = aws_s3_bucket.deliveries.id
}

output "bucket_arn" {
  description = "ARN of the DDEX deliveries bucket"
  value       = aws_s3_bucket.deliveries.arn
}

output "queue_arn" {
  description = "ARN of the DDEX delivery queue"
  value       = aws_sqs_queue.main.arn
}

output "queue_url" {
  description = "URL of the DDEX delivery queue"
  value       = aws_sqs_queue.main.url
}

output "dlq_arn" {
  description = "ARN of the dead-letter queue"
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_url" {
  description = "URL of the dead-letter queue"
  value       = aws_sqs_queue.dlq.url
}

output "task_definition_arn" {
  description = "ARN of the ddex-ingest ECS task definition, for RunTask callers"
  value       = module.ddex_ingest_task_definition.task_definition_arn
}

output "task_definition_family" {
  description = "Family name of the ddex-ingest ECS task definition"
  value       = module.ddex_ingest_task_definition.task_definition_family
}

output "task_role_arn" {
  description = "ARN of the task role, for callers that need to grant iam:PassRole"
  value       = module.ddex_ingest_task_definition.tasks_iam_role_arn
}

output "task_exec_role_arn" {
  description = "ARN of the task execution role, for callers that need to grant iam:PassRole"
  value       = module.ddex_ingest_task_definition.task_exec_iam_role_arn
}

output "security_group_id" {
  description = "Security group ID of the ddex-ingest ECS task, for RunTask network configuration"
  value       = module.ddex_ingest_task_definition.security_group_id
}
