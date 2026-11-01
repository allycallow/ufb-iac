variable "s3_media_bucket_name" {
  type    = string
  default = "production-ufb-media"
}

variable "stripe_event_bus_name" {
  description = "Name of the AWS partner event bus Stripe delivers events to (AWS EventBridge > Partner event sources - accepted once in the console, not managed here)"
  type        = string
  default     = "aws.partner/stripe.com/ed_test_61QDhFpupjNC6SV7216Q7kr4MBE9nAw6NHJIqCSEK46i"
}

variable "viewer_response_lambda_arn" {
  type    = string
  default = "arn:aws:lambda:us-east-1:081077757258:function:production-ufb-view-response:2"
}

variable "viewer_request_lambda_arn" {
  type    = string
  default = "arn:aws:lambda:us-east-1:081077757258:function:production-ufb-reviewer-request:9"
}

variable "origin_response_lambda_arn" {
  type    = string
  default = "arn:aws:lambda:us-east-1:081077757258:function:production-ufb-origin-response:94"
}

variable "google_client_id" {
  type    = string
  default = "804352256211-0ftsmn9fpvuje9v9t3v3cqhmga1v55sp.apps.googleusercontent.com"
}

variable "apple_client_id" {
  type    = string
  default = "com.upfrontbeats.ufb"
}

variable "apple_team_id" {
  type    = string
  default = "7P673D9XNB"
}

variable "apple_key_id" {
  type    = string
  default = "GJ4TSYR776"
}

variable "acme_email" {
  description = "Email address used for Teleport's Let's Encrypt ACME registration"
  type        = string
  default     = "alex@upfrontbeats.com"
}

variable "manage_redis" {
  description = "True = managed ElastiCache replication group (production-grade: multi-AZ-capable, Teleport-proxyable, ~$13/mo running 24/7). False = self-hosted Redis container on ECS (see modules/redis), for pre-launch cost savings while there's no real traffic. Currently false by deliberate choice, not just pre-launch default - revisit before going live."
  type        = bool
  default     = false
}

variable "manage_opensearch" {
  description = "True = managed OpenSearch domain (production-grade: IAM-signed access, trusted TLS, ~$30/mo running 24/7). False = self-hosted OpenSearch container on ECS (see modules/opensearch), for pre-launch cost savings while there's no real traffic. Requires ufb-search and ufb-airflow deployed with their OPENSEARCH_MANAGED support, and the self-hosted index populated via the reindex_opensearch Airflow DAG, before flipping to false."
  type        = bool
  default     = true
}

variable "cognito_certificate_arn" {
  description = "us-east-1 ACM certificate covering *.upfrontbeats.com, used for Cognito's custom Hosted UI domain"
  type        = string
  default     = "arn:aws:acm:us-east-1:081077757258:certificate/e5eb1087-ba5d-4b03-8dd9-40a321e39f48"
}

variable "track_metadata_sentry_dsn" {
  description = "Sentry DSN for track-metadata error reporting (dedicated Sentry project)."
  type        = string
  default     = "https://0ab1a064c7a68e8345959cf31a1c0e3a@o4504955106951168.ingest.us.sentry.io/4512264809742336"
  sensitive   = true
}

variable "temporal_worker_sentry_dsn" {
  description = "Sentry DSN for the Temporal worker's error reporting (dedicated Sentry project)."
  type        = string
  default     = "https://966dceb8eb769e6bd98fada0ebec1685@o4504955106951168.ingest.us.sentry.io/4512264807776256"
  sensitive   = true
}

