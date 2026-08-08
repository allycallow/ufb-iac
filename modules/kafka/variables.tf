variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnets" {
  type = list(string)
}

variable "ecs_cluster_arn" {
  type = string
}

variable "service_connect_namespace" {
  description = "Cloud Map namespace name used by ECS Service Connect, so other services can resolve the broker at kafka:9092"
  type        = string
}

variable "service_discovery_namespace_id" {
  description = "Cloud Map namespace ID used to register a plain DNS A record for the broker, so standalone RunTask tasks (which get no Service Connect proxy) can resolve kafka:9092 too"
  type        = string
}

variable "task_exec_policy_arn" {
  type = string
}

variable "client_security_group_ids" {
  description = "Security group IDs of ECS services allowed to produce/consume on the Kafka broker port (9092)"
  type        = list(string)
  default     = []
}

variable "metrics_client_security_group_ids" {
  description = "Security group IDs (e.g. the monitoring service) allowed to scrape Redpanda's Prometheus metrics on the admin port (9644)"
  type        = list(string)
  default     = []
}

variable "cpu" {
  type    = number
  default = 512
}

variable "memory" {
  type    = number
  default = 1024
}

variable "tags" {
  type    = map(string)
  default = {}
}
