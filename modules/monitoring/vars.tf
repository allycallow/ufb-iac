variable "name" {
  description = "The name of the monitoring stack."
  type        = string
}

variable "ecs_cluster_arn" {
  description = "The ARN of the ECS cluster where the monitoring service will be deployed."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "alb_target_group_arn" {
  description = "ARN of the ALB target group to associate with the ECS service"
  type        = string
}

variable "alb_security_group_id" {
  description = "ID of the security group associated with the ALB"
  type        = string
}

variable "private_subnets" {
  description = "List of private subnet IDs for the ECS service"
  type        = list(string)

}