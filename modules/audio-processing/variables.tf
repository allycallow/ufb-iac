variable "name" {
  description = "Name prefix for the SQS queues"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "media_bucket_arn" {
  description = "ARN of the S3 bucket that will trigger messages to the queue"
  type        = string
}

variable "media_bucket_id" {
  description = "ID of the S3 bucket that will trigger messages to the queue"
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

variable "private_subnets" {
  description = "List of private subnet IDs for the ECS tasks"
  type        = list(string)
}
