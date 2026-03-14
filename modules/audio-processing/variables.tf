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
