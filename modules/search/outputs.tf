output "security_group_id" {
  value = module.search_task_definition.security_group_id
}

output "opensearch_domain_endpoint" {
  value = aws_opensearch_domain.main.endpoint
}

output "opensearch_domain_arn" {
  value = aws_opensearch_domain.main.arn
}

output "opensearch_domain_name" {
  value = aws_opensearch_domain.main.domain_name
}
