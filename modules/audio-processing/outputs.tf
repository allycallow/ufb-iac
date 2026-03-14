output "queue_arn" {
  description = "ARN of the audio processing queue"
  value       = aws_sqs_queue.main.arn
}

output "queue_url" {
  description = "URL of the audio processing queue"
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
