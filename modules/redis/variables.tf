variable "name" {
  type = string
}

variable "ecs_cluster_arn" {
  type = string
}

variable "private_subnets" {
  type = list(string)
}

variable "service_connect_namespace" {
  type = string
}

variable "task_exec_policy_arn" {
  type = string
}

variable "client_security_group_ids" {
  description = "Security groups allowed to reach this container on the Redis port."
  type        = list(string)
}

variable "tags" {
  type = map(string)
}
