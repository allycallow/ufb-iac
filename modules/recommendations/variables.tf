variable "name" {
  description = "Name prefix for the SQS queues"
  type        = string
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster where the task will run"
  type        = string
}

variable "image_uri" {
  description = "URI of the container image to run in the ECS task"
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

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "alb_target_group_arn" {
  description = "ARN of the ALB target group to associate with the ECS service"
  type        = string

}

variable "secret_prefix" {
  description = "ARN prefix for Secrets Manager secrets (e.g. arn:aws:secretsmanager:region:account-id:secret:secret-name)"
  type        = string
  default     = "arn:aws:secretsmanager:eu-west-2:081077757258:secret:prod/ufb/recommendations-sQbkXb"
}

variable "table_name" {
  description = "Name of the DynamoDB table to store recommendations"
  type        = string
  default     = "ufb-recommendations"
}
