output "idempotency_table_name" {
  value = aws_dynamodb_table.idempotency.name
}

output "idempotency_table_arn" {
  value = aws_dynamodb_table.idempotency.arn
}
