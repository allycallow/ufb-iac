output "security_group_id" {
  value = module.search_task_definition.security_group_id
}

output "opensearch_domain_endpoint" {
  value = local.resolved_opensearch_domain_endpoint
}

output "opensearch_domain_arn" {
  value = local.resolved_opensearch_domain_arn
}

output "opensearch_domain_name" {
  value = try(aws_opensearch_domain.main[0].domain_name, null)
}
