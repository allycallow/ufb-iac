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
  description = "ARN of the OpenSearch domain the sink connector writes to, for scoping the task role's es:ESHttp* permissions. Empty when manage_opensearch is false (self-hosted has no IAM-based access control)."
  type        = string
}

variable "opensearch_connection_url" {
  description = "Full connection URL (scheme+host+port) the sink connector writes to - the managed domain's https://...:443, or the self-hosted container's http://opensearch:9200."
  type        = string
}

variable "manage_opensearch" {
  description = "Mirrors root var.manage_opensearch. Controls whether the sink connector's config includes AWS SigV4 signing (meaningless against the self-hosted container, which has no security plugin)."
  type        = bool
  default     = true
}

variable "audio_upload_queue_arn" {
  description = "ARN of the SQS queue the audio-upload source connector reads from, for scoping the task role's sqs:* permissions"
  type        = string
}

variable "ddex_delivery_queue_arn" {
  description = "ARN of the SQS queue the DDEX delivery source connector reads from, for scoping the task role's sqs:* permissions"
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

variable "teleport_security_group_id" {
  description = "Security group of the Teleport app-access task, allowed to reach the Connect REST API to manage connectors"
  type        = string
}

variable "monitoring_security_group_id" {
  description = "Security group of the monitoring service, allowed to scrape the jmx_prometheus_javaagent metrics port"
  type        = string
}

variable "metrics_port" {
  description = "Port jmx_prometheus_javaagent's own HTTP server listens on (set via the KAFKA_OPTS -javaagent flag)"
  type        = number
  default     = 9404
}

variable "cpu" {
  type    = number
  default = 1024
}

variable "memory" {
  type    = number
  default = 2048
}

variable "tags" {
  type    = map(string)
  default = {}
}
