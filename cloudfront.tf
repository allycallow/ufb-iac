data "aws_cloudfront_origin_request_policy" "this" {
  name = "Managed-CORS-S3Origin"
}

data "aws_cloudfront_cache_policy" "this" {
  name = "Managed-CachingOptimized"
}


resource "aws_cloudfront_response_headers_policy" "custom" {
  name    = "${terraform.workspace}-CORS-With-Preflight"
  comment = "Custom response policy"

  cors_config {
    access_control_allow_credentials = true

    access_control_allow_headers {
      items = ["Credentials", "Authorization"]
    }

    access_control_allow_methods {
      items = ["GET", "POST", "HEAD", "OPTIONS"]
    }

    access_control_allow_origins {
      items = [
        "https://*.${local.domain}",
        "https://${local.domain}",
        "https://local.${local.domain}:3000"
      ]
    }

    access_control_max_age_sec = 600

    origin_override = false
  }
}

resource "random_id" "media_id" {
  byte_length = 8
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity_media" {
  comment = ""
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity_frontend" {
  comment = ""
}

resource "aws_cloudfront_public_key" "cf_media_key" {
  encoded_key = tls_private_key.media.public_key_pem
}

resource "aws_cloudfront_key_group" "cf_media_keygroup" {
  items = [aws_cloudfront_public_key.cf_media_key.id]
  name  = "${random_id.media_id.hex}-group"
}

resource "aws_cloudfront_distribution" "media" {
  enabled      = true
  http_version = "http2and3"
  aliases      = terraform.workspace == "dev" ? ["dev-cdn.${local.domain}"] : ["cdn.${local.domain}"]

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = "arn:aws:acm:us-east-1:081077757258:certificate/e5eb1087-ba5d-4b03-8dd9-40a321e39f48"
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  origin {
    domain_name = aws_s3_bucket.media.bucket_domain_name
    origin_id   = aws_s3_bucket.media.id
    origin_path = "/production-ufb-media"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity_media.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = aws_s3_bucket.media.id
    viewer_protocol_policy   = "redirect-to-https"
    min_ttl                  = 0
    default_ttl              = terraform.workspace == "dev" ? 0 : 604800
    max_ttl                  = terraform.workspace == "dev" ? 0 : 31536000
    compress                 = true
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.this.id
    cache_policy_id          = data.aws_cloudfront_cache_policy.this.id
  }

  ordered_cache_behavior {
    path_pattern               = "/audio/*"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    target_origin_id           = aws_s3_bucket.media.id
    min_ttl                    = 0
    default_ttl                = 3600
    max_ttl                    = 86400
    compress                   = true
    viewer_protocol_policy     = "redirect-to-https"
    trusted_key_groups         = [aws_cloudfront_key_group.cf_media_keygroup.id]
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.this.id
    cache_policy_id            = data.aws_cloudfront_cache_policy.this.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.custom.id
  }

  ordered_cache_behavior {
    path_pattern             = "/images/*"
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    target_origin_id         = aws_s3_bucket.media.id
    min_ttl                  = 0
    default_ttl              = 3600
    max_ttl                  = 86400
    compress                 = true
    viewer_protocol_policy   = "redirect-to-https"
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.this.id
    cache_policy_id          = data.aws_cloudfront_cache_policy.this.id

    lambda_function_association {
      event_type   = "viewer-response"
      lambda_arn   = var.viewer_response_lambda_arn
      include_body = false
    }

    lambda_function_association {
      event_type   = "viewer-request"
      lambda_arn   = var.viewer_request_lambda_arn
      include_body = false
    }

    lambda_function_association {
      event_type   = "origin-response"
      lambda_arn   = var.origin_response_lambda_arn
      include_body = false
    }
  }

  ordered_cache_behavior {
    path_pattern             = "/static/*"
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    target_origin_id         = aws_s3_bucket.media.id
    min_ttl                  = 0
    default_ttl              = 3600
    max_ttl                  = 86400
    compress                 = true
    viewer_protocol_policy   = "redirect-to-https"
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.this.id
    cache_policy_id          = data.aws_cloudfront_cache_policy.this.id
  }
}


resource "aws_cloudfront_distribution" "frontend" {
  enabled      = true
  http_version = "http2and3"
  aliases      = ["production.${local.domain}"]

  viewer_certificate {
    acm_certificate_arn      = "arn:aws:acm:us-east-1:081077757258:certificate/e5eb1087-ba5d-4b03-8dd9-40a321e39f48"
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  origin {
    domain_name = module.alb.dns_name
    origin_id   = "frontend-alb-origin"

    custom_origin_config {
      origin_protocol_policy = "https-only"
      http_port              = 80
      https_port             = 443
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  ordered_cache_behavior {
    path_pattern     = "/_next/static/*"
    target_origin_id = "frontend-alb-origin"

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    compress = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }

      headers = ["*"]
    }

    min_ttl     = 0
    default_ttl = 31536000
    max_ttl     = 31536000
  }

  ordered_cache_behavior {
    path_pattern     = "/public/*"
    target_origin_id = "frontend-alb-origin"

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    compress = true

    forwarded_values {
      query_string = true
      headers      = ["*"]

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 2592000
    max_ttl     = 2592000
  }

  default_cache_behavior {
    target_origin_id       = "frontend-alb-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    compress = true

    forwarded_values {
      query_string = true

      headers = ["*"]

      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}


output "cloudfront_dist_media_id" {
  value = aws_cloudfront_distribution.media.id
}

output "media_cf_url" {
  value = "https://${aws_cloudfront_distribution.media.domain_name}"
}

output "cf_media_keygroup_id" {
  value = aws_cloudfront_key_group.cf_media_keygroup.id
}

output "cf_media_key_id" {
  value = aws_cloudfront_public_key.cf_media_key.id
}
