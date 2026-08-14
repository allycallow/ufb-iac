# Media Bucket

resource "aws_s3_bucket" "media" {
  bucket = var.s3_media_bucket_name
}

resource "aws_s3_bucket_cors_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = [
      "https://*.${var.domain}",
      "https://${var.domain}",
      "https://local.${var.domain}:3000"
    ]
    expose_headers  = []
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# WAV originals and their HLS/DRM derivatives share the same audio/ prefix
# (distinguished only by extension - see the .wav suffix filter in
# modules/audio-processing/main.tf), so a prefix-based lifecycle rule can't
# tell them apart. Instead this targets the archive-tier=source tag, which
# the audio-processing task applies to a WAV object only after it has been
# transcoded successfully - untagged (unprocessed, or still-processing)
# objects are never matched and stay in Standard.
resource "aws_s3_bucket_lifecycle_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    id     = "archive-processed-wav-originals"
    status = "Enabled"

    filter {
      tag {
        key   = "archive-tier"
        value = "source"
      }
    }

    transition {
      days          = var.wav_archive_after_days
      storage_class = "DEEP_ARCHIVE"
    }
  }
}

# Events Bucket

resource "aws_s3_bucket" "events" {
  bucket = "${var.name}-events"
}

resource "aws_s3_bucket_public_access_block" "events" {
  bucket = aws_s3_bucket.events.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket      = aws_s3_bucket.events.id
  eventbridge = true
}

# Data Warehouse

resource "aws_s3_bucket" "data_warehouse" {
  bucket = "${var.name}-data-warehouse"
}

# Processed Queries

resource "aws_s3_bucket" "data_processed" {
  bucket = "${var.name}-data-processed"
}

# Frontend

resource "aws_s3_bucket" "frontend" {
  bucket = "${var.name}-frontend"
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls   = false
  block_public_policy = false
}

resource "aws_s3_bucket_cors_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}
