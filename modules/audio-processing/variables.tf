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

variable "event_bus_arn" {
  description = "ARN of the EventBridge bus to publish progress events to"
  type        = string
}

variable "kafka_bootstrap_servers" {
  description = "Kafka broker address reachable over normal VPC DNS (this task runs standalone via RunTask, so it gets no Service Connect proxy and can't use the `kafka` short name)"
  type        = string
}

variable "download_content_keys_kms_key_arn" {
  description = "ARN of the KMS key that wraps per-track AES content keys for offline download assets - this task is granted kms:Encrypt on it"
  type        = string
}

variable "ddex_delivery_bucket_arn" {
  description = "ARN of the DDEX delivery bucket - DdexDeliveryWorkflow starts this task directly against it, so it needs s3:GetObject here too (not just the KMS decrypt grant modules/ddex-delivery's CMK policy already gives this role)"
  type        = string
}
