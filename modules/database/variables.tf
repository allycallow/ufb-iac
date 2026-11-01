variable "name" {
  type = string
}

variable "database_subnet_group" {
  type = string
}

variable "rds_sg_id" {
  type = string
}

variable "elasticache_sg_id" {
  type = string
}

variable "elasticache_subnet_group" {
  type = string
}

variable "manage_redis" {
  description = "Whether to create the managed ElastiCache replication group. False during pre-launch testing, where a self-hosted Redis container on ECS (see modules/redis) stands in instead to save the ~$13/mo this runs 24/7 for almost no traffic. Flip back to true and apply to restore this exactly as-is."
  type        = bool
  default     = true
}
