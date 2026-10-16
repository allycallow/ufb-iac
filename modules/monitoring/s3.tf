resource "aws_s3_bucket" "tempo_traces" {
  bucket        = "${var.name}-tempo-traces"
  force_destroy = false

  tags = {
    Name        = "Tempo Traces Storage"
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}

# 2. Block All Public Access (Crucial for security)
resource "aws_s3_bucket_public_access_block" "tempo_traces_security" {
  bucket = aws_s3_bucket.tempo_traces.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 3. Ensure Bucket Ownership Controls default to Bucket Owner Enforced (disables ACLs)
resource "aws_s3_bucket_ownership_controls" "tempo_traces_ownership" {
  bucket = aws_s3_bucket.tempo_traces.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# 4. Enable Server-Side Encryption (Best practice)
resource "aws_s3_bucket_server_side_encryption_configuration" "tempo_traces_encryption" {
  bucket = aws_s3_bucket.tempo_traces.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Dashboard JSON storage. ECS task definitions cap out at 64KB total — fine
# for one small dashboard embedded directly in the Grafana container's
# command (see the stripe-webhook-dlq heredoc below), but six dashboards'
# worth of panel JSON blew well past that limit. Dashboards live here
# instead, and the "dashboard-sync" sidecar below pulls them onto a shared
# volume before Grafana starts — the same config-writer-sidecar pattern
# modules/kafka-connect uses for connector configs.
resource "aws_s3_bucket" "grafana_dashboards" {
  bucket        = "${var.name}-grafana-dashboards"
  force_destroy = true

  tags = {
    Name        = "Grafana Dashboard Storage"
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "grafana_dashboards_security" {
  bucket = aws_s3_bucket.grafana_dashboards.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "grafana_dashboards_ownership" {
  bucket = aws_s3_bucket.grafana_dashboards.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "grafana_dashboards_encryption" {
  bucket = aws_s3_bucket.grafana_dashboards.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "dashboards" {
  for_each = {
    "stripe-webhook-dlq.json" = var.stripe_webhook_dlq_dashboard_json
    "recommendations.json"    = var.recommendations_dashboard_json
    "search.json"             = var.search_dashboard_json
    "airflow.json"            = var.airflow_dashboard_json
    "backend.json"            = var.backend_dashboard_json
    "temporal-worker.json"    = var.temporal_worker_dashboard_json
    "kafka-connect.json"      = var.kafka_connect_dashboard_json
  }

  bucket  = aws_s3_bucket.grafana_dashboards.id
  key     = "dashboards/${each.key}"
  content = each.value
}
