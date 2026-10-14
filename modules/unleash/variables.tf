variable "name" {
  description = "Resource name prefix, e.g. production-ufb-unleash"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "account_id" {
  description = "Used to scope the DB-bootstrap task's assume-role policy to this account."
  type        = string
}

variable "region" {
  type = string
}

# ── Shared infrastructure handed in from the root stack ────────────────────────

variable "ecs_cluster_arn" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnets" {
  type = list(string)
}

variable "task_exec_policy_arn" {
  description = "Shared task-execution policy from the ecs-cluster module."
  type        = string
}

variable "service_connect_namespace" {
  description = "Cloud Map namespace name used by ECS Service Connect, so in-cluster services (e.g. monitoring) can reach Unleash as unleash:4242 without hairpinning through the public ALB."
  type        = string
}

variable "alb_security_group_id" {
  type = string
}

variable "alb_target_group_arn" {
  type = string
}

variable "monitoring_security_group_id" {
  description = "Allowed to scrape Unleash's Prometheus endpoint at /internal-backstage/prometheus."
  type        = string
}

# ── Existing RDS PostgreSQL (modules/database) ────────────────────────────────

variable "db_host" {
  description = "Hostname of the existing RDS PostgreSQL instance, without the port."
  type        = string
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "db_name" {
  type    = string
  default = "unleash"
}

variable "db_username" {
  type    = string
  default = "unleash"
}

variable "db_secret_name" {
  description = "Secrets Manager secret name for the dedicated Unleash DB credentials, following this repo's prod/ufb/<service> convention (see modules/backend, modules/airflow)."
  type        = string
  default     = "prod/ufb/unleash"
}

variable "db_master_secret_arn" {
  description = <<-EOT
    RDS-managed master credentials secret (module.database.db_instance_master_user_secret_arn).
    Used only by the one-off db-bootstrap task to create the dedicated `unleash`
    role/database — never by the long-running service, which uses its own
    non-rotating secret (db_secret_arn output).
  EOT
  type        = string
}

variable "db_bootstrap_database" {
  description = "Existing database the bootstrap task connects to in order to issue CREATE ROLE / CREATE DATABASE."
  type        = string
  default     = "postgres"
}

# ── Unleash server ────────────────────────────────────────────────────────────

variable "image" {
  description = "Official Unleash server image. Always pin a tag."
  type        = string
  default     = "unleashorg/unleash-server:6.7.2"
}

variable "port" {
  type    = number
  default = 4242
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  description = "Single instance by default, matching the cost-conscious topology used elsewhere in this repo (see modules/temporal). Flag state lives in Postgres, so a task replacement is a brief availability blip, not data loss."
  type        = number
  default     = 1
}

variable "log_level" {
  type    = string
  default = "warn"
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "readonly_root_filesystem" {
  description = "Unleash writes no state to disk — everything lives in Postgres. Set to false if a future image version needs scratch space (e.g. for npm/node temp files)."
  type        = bool
  default     = true
}
