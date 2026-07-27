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
  description = "Cloud Map namespace name used by ECS Service Connect"
  type        = string
}

variable "task_exec_policy_arn" {
  type = string
}

variable "image_uri" {
  description = "URI of the Kafka Connect container image (distributed worker + Aiven OpenSearch sink connector plugin)"
  type        = string
}

variable "opensearch_domain_arn" {
  description = "ARN of the OpenSearch domain the sink connector writes to, for scoping the task role's es:ESHttp* permissions"
  type        = string
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
