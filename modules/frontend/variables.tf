variable "name" {
  description = "Name for the frontend ECS service"
  type        = string
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  type        = string
}

variable "image_uri" {
  description = "URI of the frontend container image"
  type        = string
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB"
  type        = string
}

variable "private_subnets" {
  description = "List of private subnet IDs for the ECS service"
  type        = list(string)
}

variable "alb_target_group_arn" {
  description = "ARN of the ALB target group for the frontend"
  type        = string
}

variable "service_connect_namespace" {
  description = "Cloud Map namespace name used by ECS Service Connect"
  type        = string
}

variable "task_exec_policy_arn" {
  description = "ARN of the shared ECS task execution IAM policy"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
