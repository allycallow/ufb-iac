output "sessions_table_name" {
  value = aws_dynamodb_table.sessions.name
}

output "ledger_table_name" {
  value = aws_dynamodb_table.ledger.name
}
