output "user_pool_id" {
  value = aws_cognito_user_pool.pool.id
}

output "user_pool_arn" {
  value = aws_cognito_user_pool.pool.arn
}

output "user_pool_name" {
  value = aws_cognito_user_pool_client.client.name
}

output "user_pool_web_client_id" {
  value = aws_cognito_user_pool_client.client.id
}
