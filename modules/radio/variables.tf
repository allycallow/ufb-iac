variable "name" {
  type = string
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster where the radio task will run"
  type        = string
}

variable "private_subnets" {
  description = "List of private subnet IDs for the ECS task"
  type        = list(string)
}

variable "image_uri" {
  description = "URI of the container image running Liquidsoap + the HLS/S3 sync loop"
  type        = string
}

variable "media_bucket_arn" {
  description = "ARN of the media bucket - the radio/ prefix holds the stub playlist and the live HLS output"
  type        = string
}

variable "media_bucket_name" {
  description = "Name of the media bucket, passed into the container so it knows where to read the playlist from and write HLS segments to"
  type        = string
}
