variable "name" {
  description = "Name for the backend ECS service"
  type        = string
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  type        = string
}

variable "image_uri" {
  description = "URI of the backend container image"
  type        = string
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB"
  type        = string
}

variable "monitoring_security_group_id" {
  description = "Security group ID of the monitoring ECS service"
  type        = string
}

variable "frontend_security_group_id" {
  description = "Security group ID of the frontend ECS service"
  type        = string
}

variable "private_subnets" {
  description = "List of private subnet IDs for the ECS service"
  type        = list(string)
}

variable "alb_target_group_arn" {
  description = "ARN of the ALB target group for the backend"
  type        = string
}

variable "service_connect_namespace" {
  description = "Cloud Map namespace name used by ECS Service Connect"
  type        = string
}

variable "db_endpoint" {
  description = "RDS instance endpoint hostname (without port)"
  type        = string
}

variable "media_bucket_name" {
  description = "Name of the S3 media bucket"
  type        = string
}

variable "media_bucket_arn" {
  description = "ARN of the S3 media bucket"
  type        = string
}

variable "cognito_user_pool_id" {
  description = "ID of the Cognito user pool"
  type        = string
}

variable "cognito_app_client_id" {
  description = "ID of the Cognito app client"
  type        = string
}

variable "cognito_user_pool_arn" {
  description = "ARN of the Cognito user pool"
  type        = string
}

variable "cf_media_key_id" {
  description = "ID of the CloudFront public key for media signing"
  type        = string
}

variable "cf_preview_key_id" {
  description = "ID of the CloudFront public key for preview (auth-only) signing"
  type        = string
}

variable "event_bus_name" {
  description = "Name of the EventBridge event bus"
  type        = string
}

variable "event_bus_arn" {
  description = "ARN of the EventBridge event bus"
  type        = string
}

variable "redis_host" {
  description = "Hostname of the ElastiCache Redis node"
  type        = string
}

variable "secret_prefix" {
  description = "ARN prefix for the backend Secrets Manager secret"
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
