output "proxy_public_addr" {
  value = "${var.public_addr}:443"
}

output "ecs_service_name" {
  value = module.teleport_task_definition.name
}

output "security_group_id" {
  value = module.teleport_task_definition.security_group_id
}
