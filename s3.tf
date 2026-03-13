# Media Bucket

data "aws_iam_policy_document" "media" {
  statement {
    actions = ["s3:GetObject"]
    resources = [
      "arn:aws:s3:::${var.s3_media_bucket_name}",
      "arn:aws:s3:::${var.s3_media_bucket_name}/*"
    ]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity_media.iam_arn]
    }
  }
}

resource "aws_s3_bucket" "media" {
  bucket = var.s3_media_bucket_name
}

resource "aws_s3_bucket_cors_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = [
      "https://*.${local.domain}",
      "https://${local.domain}",
      "https://local.upfrontbeats.com:3000"
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

resource "aws_s3_bucket_public_access_block" "events" {
  bucket = aws_s3_bucket.events.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "allow_access_cloudfront" {
  bucket = aws_s3_bucket.media.id
  policy = data.aws_iam_policy_document.media.json
}

# Events Bucket

resource "aws_s3_bucket" "events" {
  bucket = "${local.name}-events"
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket      = aws_s3_bucket.events.id
  eventbridge = true
}

#  Warehouse

resource "aws_s3_bucket" "data_warehouse" {
  bucket = "${local.name}-data-warehouse"
}

## Process queries

resource "aws_s3_bucket" "data_processed" {
  bucket = "${local.name}-data-processed"
}

# Frontend

resource "aws_s3_bucket" "frontend" {
  bucket = "${local.name}-frontend"
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


data "aws_iam_policy_document" "frontend" {
  statement {
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.frontend.arn}",
      "${aws_s3_bucket.frontend.arn}/*"
    ]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity_frontend.iam_arn]
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "example" {
  bucket = aws_s3_bucket.frontend.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend.json
}

# Outputs

output "s3_media_bucket_name" {
  value = aws_s3_bucket.media.id
}

output "s3_event_bucket_name" {
  value = aws_s3_bucket.events.id
}

output "s3_data_warehouse_bucket_name" {
  value = aws_s3_bucket.data_warehouse.id
}

output "s3_data_processed_bucket_name" {
  value = aws_s3_bucket.data_processed.id
}

output "frontend_bucket_name" {
  value = aws_s3_bucket.frontend.id
}
