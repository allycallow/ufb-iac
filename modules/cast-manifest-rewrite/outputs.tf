output "qualified_arn" {
  description = "Versioned ARN — required for a CloudFront lambda_function_association (an unqualified/$LATEST ARN is rejected)."
  value       = aws_lambda_function.this.qualified_arn
}
