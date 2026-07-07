variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnets" {
  type = list(string)
}

variable "private_subnets" {
  type = list(string)
}

variable "ecs_cluster_arn" {
  type = string
}

variable "task_exec_policy_arn" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "public_addr" {
  description = "Public DNS name the Teleport proxy will be reachable on"
  type        = string
  default     = "teleport.upfrontbeats.com"
}

variable "acme_email" {
  description = "Email address used for Let's Encrypt ACME registration"
  type        = string
}

variable "db_instance_endpoint" {
  description = "RDS Postgres endpoint, host:port"
  type        = string
}

variable "db_instance_identifier" {
  type = string
}

variable "db_instance_resource_id" {
  description = "RDS DbiResourceId, used to scope the rds-db:connect IAM permission"
  type        = string
}

variable "teleport_db_username" {
  description = "Postgres username Teleport connects as via IAM auth (must be granted the rds_iam role on the DB, see plan's manual steps)"
  type        = string
  default     = "teleport_svc"
}

variable "redis_replication_group_id" {
  description = "ElastiCache replication group ID, used so Teleport can look up the engine version for IAM auth support detection"
  type        = string
}

variable "redis_endpoint" {
  description = "ElastiCache Redis endpoint, host:port"
  type        = string
}

variable "opensearch_domain_endpoint" {
  type = string
}

variable "opensearch_domain_arn" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
