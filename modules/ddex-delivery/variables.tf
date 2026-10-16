variable "name" {
  description = "Name prefix for the S3 bucket, SQS queues, and ECS task"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster where the ingest task will run"
  type        = string
}

variable "image_uri" {
  description = "URI of the container image to run in the ECS task"
  type        = string
}

variable "private_subnets" {
  description = "List of private subnet IDs for the ECS task"
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

variable "processed_delivery_archive_after_days" {
  description = "Days after upload before a delivery object tagged ddex-processed=true (set by ddex-ingest once a delivery has been checksum-verified and ingested) transitions to Glacier Deep Archive. Kept indefinitely after that as a cheap record of exactly what was delivered, rather than expired."
  type        = number
  default     = 3
}

variable "s3_vpc_endpoint_id" {
  description = "ID of the VPC's S3 Gateway endpoint. Reads of delivery objects are denied unless they come through this endpoint, so a leaked credential is useless for exfiltrating assets from outside the VPC - only partner uploads (PutObject from the public internet) remain unaffected."
  type        = string
}

variable "audio_processing_task_role_arn" {
  description = "Task role ARN of the audio-processing ECS task - granted kms:Decrypt on the delivery CMK so it can encode a DDEX-delivered audio file directly from this bucket."
  type        = string
}

variable "track_metadata_task_role_arn" {
  description = "Task role ARN of the track-metadata ECS task - granted kms:Decrypt on the delivery CMK so it can analyze a DDEX-delivered audio file directly from this bucket."
  type        = string
}

variable "stale_delivery_retention_days" {
  description = "Fallback expiration for delivery objects that never get tagged ddex-processed=true - e.g. a delivery that failed validation and was never retried. Long enough to debug, short enough that abandoned deliveries don't accumulate indefinitely."
  type        = number
  default     = 90
}

variable "media_bucket_name" {
  description = "Name of the media bucket CloudFront serves from - ddex-ingest stages a release's cover art there (under a disposable prefix) since the backend already has read/write access to it, avoiding any need to widen this module's own KMS-restricted bucket to a new principal."
  type        = string
}

variable "media_bucket_arn" {
  description = "ARN of the media bucket, for the staging IAM grant"
  type        = string
}
