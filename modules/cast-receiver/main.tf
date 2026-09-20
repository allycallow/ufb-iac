resource "aws_s3_bucket" "this" {
  bucket = "${var.name}-cast-receiver"
}

resource "aws_s3_bucket_website_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  index_document {
    suffix = "index.html"
  }
}

# S3 website endpoints don't support Origin Access Control/Identity the way
# REST endpoints do, so CloudFront has to reach this bucket as a plain HTTP
# custom origin — meaning the objects have to be publicly readable
# regardless. That's fine here: this page carries no auth and needs to be
# fetchable by any Chromecast device on the internet anyway.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls   = false
  block_public_policy = false
}

data "aws_iam_policy_document" "public_read" {
  statement {
    sid       = "PublicReadGetObject"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.public_read.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# The receiver's source lives in this module's own files/ directory — it's
# a standalone static page, unrelated to ufb-frontend's Next.js build, kept
# here so its entire deploy is driven by `terraform apply`.
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.this.id
  key          = "index.html"
  source       = "${path.module}/files/index.html"
  etag         = filemd5("${path.module}/files/index.html")
  content_type = "text/html"
}

resource "aws_s3_object" "receiver_js" {
  bucket       = aws_s3_bucket.this.id
  key          = "receiver.js"
  source       = "${path.module}/files/receiver.js"
  etag         = filemd5("${path.module}/files/receiver.js")
  content_type = "application/javascript"
}

resource "aws_cloudfront_distribution" "this" {
  enabled      = true
  http_version = "http2and3"
  price_class  = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # No custom alias/ACM cert: Google Cast only needs *an* HTTPS URL, and
  # CloudFront's default *.cloudfront.net certificate covers that without
  # depending on this account's wildcard cert or a Route 53 record. Add an
  # alias later if a branded URL ever matters.
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  origin {
    domain_name = aws_s3_bucket_website_configuration.this.website_endpoint
    origin_id   = "cast-receiver-s3-website"

    # S3 website endpoints are HTTP-only.
    custom_origin_config {
      origin_protocol_policy = "http-only"
      http_port              = 80
      https_port             = 443
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "cast-receiver-s3-website"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }
}
