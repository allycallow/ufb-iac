output "cluster_arn" {
  value = module.ecs_cluster.arn
}

output "cluster_name" {
  value = var.name
}

output "task_exec_policy_arn" {
  value = aws_iam_policy.ecs_task_exec_policy.arn
}

output "service_discovery_namespace_name" {
  value = aws_service_discovery_private_dns_namespace.ecs.name
}
