output "sessions_table_name" {
  value = aws_dynamodb_table.sessions.name
}

output "ledger_table_name" {
  value = aws_dynamodb_table.ledger.name
}

output "ledger_stream_arn" {
  description = "ARN of the ledger table's DynamoDB stream"
  value       = aws_dynamodb_table.ledger.stream_arn
}

output "ledger_stream_dlq_arn" {
  description = "ARN of the dead-letter queue for ledger stream batches the Lambda could not process"
  value       = aws_sqs_queue.ledger_stream_dlq.arn
}
