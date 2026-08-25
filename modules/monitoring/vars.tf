variable "name" {
  description = "The name of the monitoring stack."
  type        = string
}

variable "ecs_cluster_arn" {
  description = "The ARN of the ECS cluster where the monitoring service will be deployed."
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "alb_target_group_arn" {
  description = "ARN of the ALB target group to associate with the ECS service"
  type        = string
}

variable "alb_security_group_id" {
  description = "ID of the security group associated with the ALB"
  type        = string
}

variable "private_subnets" {
  description = "List of private subnet IDs for the ECS service"
  type        = list(string)

}

variable "vpc_cidr_block" {
  description = "CIDR block of the VPC, used to allow internal traffic"
  type        = string
}

variable "service_connect_namespace" {
  description = "AWS Service Connect namespace for inter-service discovery"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID used for the EFS security group"
  type        = string
}

variable "kafka_admin_target" {
  description = "host:port for Redpanda's Prometheus metrics (its admin API, e.g. \"kafka:9644\"). Null skips the scrape job."
  type        = string
  default     = null
}

variable "temporal_metrics_targets" {
  description = "host:port list for the Temporal server's built-in Prometheus endpoint, one per role. Empty list skips the scrape job."
  type        = list(string)
  default     = []
}

variable "stripe_webhook_dlq_dashboard_json" {
  description = "Raw JSON content of the Stripe webhook DLQ Grafana dashboard, provisioned into Grafana on container start"
  type        = string
}
