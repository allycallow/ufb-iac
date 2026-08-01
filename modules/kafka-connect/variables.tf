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

variable "audio_upload_queue_arn" {
  description = "ARN of the SQS queue the audio-upload source connector reads from, for scoping the task role's sqs:* permissions"
  type        = string
}

variable "debezium_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the debezium replication user's credentials, referenced by the outbox source connector config via the secretsmanager config provider"
  type        = string
}

variable "db_host" {
  description = "Bare hostname (no port) of the ufb Postgres instance, for the Debezium outbox source connector config"
  type        = string
}

variable "db_name" {
  description = "Database name the Debezium outbox source connector connects to"
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
