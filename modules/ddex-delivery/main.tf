data "aws_caller_identity" "current" {}

# Deliveries land under partners/<dpid>/... so a per-partner IAM policy can
# later scope access to "${aws_s3_bucket.deliveries.arn}/partners/<dpid>/*"
# once a given distributor's credentials are issued. No such scoping exists
# yet - every partner currently shares this bucket.
resource "aws_s3_bucket" "deliveries" {
  bucket = var.name

  tags = merge(var.tags, {
    Name = var.name
  })
}

# Delivered WAVs/art aren't needed in Standard storage once ingested, but
# they're the only record of exactly what a partner delivered and when - a
# receipt worth keeping cheaply rather than deleting, in case a dispute ever
# comes up over what was actually sent. Deep Archive runs ~$0.001/GB-month,
# so retaining every delivery indefinitely is effectively free.
#
# The tag-based rule depends on ddex-ingest tagging an object
# ddex-processed=true once it's checksum-verified and ingested - that
# tagging doesn't exist yet (ddex-ingest is still a stub), so this rule is a
# no-op until that's built. The untagged rule is the fallback for deliveries
# that fail validation and never get tagged - those have no compliance value
# (they were never a confirmed, ingested delivery), so they're deleted
# rather than archived, just so storage doesn't grow unbounded while a
# broken delivery is being debugged.
resource "aws_s3_bucket_lifecycle_configuration" "deliveries" {
  bucket = aws_s3_bucket.deliveries.id

  rule {
    id     = "archive-processed-deliveries"
    status = "Enabled"

    filter {
      tag {
        key   = "ddex-processed"
        value = "true"
      }
    }

    transition {
      days          = var.processed_delivery_archive_after_days
      storage_class = "DEEP_ARCHIVE"
    }
  }

  rule {
    id     = "expire-stale-deliveries"
    status = "Enabled"

    filter {
      prefix = "partners/"
    }

    expiration {
      days = var.stale_delivery_retention_days
    }
  }
}

resource "aws_s3_bucket_public_access_block" "deliveries" {
  bucket = aws_s3_bucket.deliveries.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-dlq"
  message_retention_seconds = 1209600

  tags = merge(var.tags, {
    Name = "${var.name}-dlq"
  })
}

resource "aws_sqs_queue" "main" {
  name                       = var.name
  visibility_timeout_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(var.tags, {
    Name = var.name
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main.arn]
  })
}

# ERN deliveries are a manifest XML plus the resource files (audio, art) it
# references. Distributors conventionally upload the manifest last, once all
# referenced resources are already in place, so filtering on the manifest's
# .xml suffix is what signals "this delivery is complete" rather than
# triggering ingestion once per resource file.
resource "aws_s3_bucket_notification" "delivery_events" {
  bucket = aws_s3_bucket.deliveries.id

  queue {
    queue_arn     = aws_sqs_queue.main.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "partners/"
    filter_suffix = ".xml"
  }

  depends_on = [aws_sqs_queue_policy.allow_s3]
}
