output "task_definition_arn" {
  description = "ARN of the track-metadata ECS task definition, for RunTask callers"
  value       = module.track_metadata_processing_task_definition.task_definition_arn
}

output "task_definition_family" {
  description = "Family name of the track-metadata ECS task definition"
  value       = module.track_metadata_processing_task_definition.task_definition_family
}

output "task_role_arn" {
  description = "ARN of the task role, for callers that need to grant iam:PassRole"
  value       = module.track_metadata_processing_task_definition.tasks_iam_role_arn
}

output "task_exec_role_arn" {
  description = "ARN of the task execution role, for callers that need to grant iam:PassRole"
  value       = module.track_metadata_processing_task_definition.task_exec_iam_role_arn
}

output "security_group_id" {
  description = "Security group ID of the track-metadata ECS task, for RunTask network configuration"
  value       = module.track_metadata_processing_task_definition.security_group_id
}
