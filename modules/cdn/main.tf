data "aws_cloudfront_origin_request_policy" "this" {
  name = "Managed-CORS-S3Origin"
}

# Same CORS-supporting headers as Managed-CORS-S3Origin above, but also
# forwards the query string to origin — needed only on the /audio/* (cmaf)
# behavior below, so cast-manifest-rewrite's origin-response Lambda can
# read a signed Cast request's query string and propagate it into the
# manifest it rewrites. Origin request policies control what's forwarded
# to origin independently of caching, unlike a cache policy's
# query_strings_config, which CloudFront rejects setting to anything but
# "none" when that cache policy has caching fully disabled (as
# audio_segments below does).
resource "aws_cloudfront_origin_request_policy" "audio_cmaf_with_querystring" {
  name    = "${terraform.workspace}-audio-cmaf-with-querystring"
  comment = "Managed-CORS-S3Origin, plus forwarding the query string a Cast signed URL carries."

  cookies_config {
    cookie_behavior = "none"
  }

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = [
        "Origin",
        "Access-Control-Request-Headers",
        "Access-Control-Request-Method",
      ]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

data "aws_cloudfront_cache_policy" "this" {
  name = "Managed-CachingOptimized"
}

resource "random_id" "media_id" {
  byte_length = 8
}

resource "aws_cloudfront_origin_access_identity" "media" {
  comment = ""
}

resource "aws_cloudfront_origin_access_identity" "frontend" {
  comment = ""
}

resource "aws_cloudfront_public_key" "cf_media_key" {
  encoded_key = var.media_public_key_pem
}

resource "aws_cloudfront_key_group" "cf_media_keygroup" {
  items = [aws_cloudfront_public_key.cf_media_key.id]
  name  = "${random_id.media_id.hex}-group"
}

# Separate trust tier for preview cookies. Full-track cookies are never
# signed with this key, so they can't unlock the /audio/* (full-track)
# behavior even if a signed cookie's Resource policy were scoped too broadly.
resource "aws_cloudfront_public_key" "cf_preview_key" {
  encoded_key = var.preview_public_key_pem
}

resource "aws_cloudfront_key_group" "cf_preview_keygroup" {
  items = [aws_cloudfront_public_key.cf_preview_key.id]
  name  = "${random_id.media_id.hex}-preview-group"
}

# Separate trust tier for download assets. These objects are already
# AES-encrypted before upload (see ufb-audio-processing's
# encrypt_download_asset), so this signature only controls who can fetch the
# ciphertext at all - it is not the thing standing between a leaked URL and
# playable audio.
resource "aws_cloudfront_public_key" "cf_download_key" {
  encoded_key = var.download_public_key_pem
}

resource "aws_cloudfront_key_group" "cf_download_keygroup" {
  items = [aws_cloudfront_public_key.cf_download_key.id]
  name  = "${random_id.media_id.hex}-download-group"
}

resource "aws_cloudfront_cache_policy" "audio_segments" {
  name    = "${terraform.workspace}-audio-segments-no-cache"
  comment = "Zero-TTL for encrypted CMAF segments. Prevents 304s that break DRM session decryption."

  default_ttl = 0
  min_ttl     = 0
  max_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = false
    enable_accept_encoding_gzip   = false

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    # CloudFront rejects any query_string_behavior other than "none" on a
    # cache policy with caching fully disabled (min/default/max TTL all 0,
    # as above) — "InvalidArgument: The parameter QueryStringBehavior is
    # invalid for policy with caching disabled." Forwarding the signed
    # Cast request's query string to origin (so cast-manifest-rewrite's
    # origin-response Lambda can read and propagate it) is handled instead
    # by the audio_cmaf_with_querystring origin request policy below,
    # which is independent of caching.
    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

# The live manifest rewrites on every segment rotation, so it can never be
# cached - a stale manifest hands listeners segment URIs that have already
# aged out of the live window. Segments themselves don't need a dedicated
# policy: each filename is unique (see modules/radio), so the standard
# Managed-CachingOptimized policy used elsewhere in this file already does
# the right thing for them.
resource "aws_cloudfront_cache_policy" "radio_manifest" {
  name    = "${terraform.workspace}-radio-manifest-no-cache"
  comment = "Zero-TTL for the live radio HLS manifest."

  default_ttl = 0
  min_ttl     = 0
  max_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = false
    enable_accept_encoding_gzip   = false

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_cache_policy" "images_immutable" {
  name    = "${terraform.workspace}-images-immutable"
  comment = "Long TTL for resized image derivatives - key encodes width/format/quality so bytes never change once generated."

  default_ttl = 31536000
  min_ttl     = 1
  max_ttl     = 31536000

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
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
        "https://*.${var.domain}",
        "https://${var.domain}",
        "https://local.${var.domain}:3000",
        "https://local.${var.domain}:3001",
      ]
    }

    access_control_max_age_sec = 600

    origin_override = false
  }
}

# The radio stream is public and unauthenticated (no signed cookies, unlike
# the rest of the catalog), so unlike `custom` above this allows any origin -
# with no credentials in play there's nothing a wildcard origin exposes.
# Without this, Safari's native HLS engine enforces CORS on the
# playlist/segment sub-fetches even for a same-page <audio> element whenever
# the page's own origin differs from the stream's, and fails silently
# (a bare MediaError with no message) - this is what actually broke
# playback testing this, not a stream/encoding problem.
resource "aws_cloudfront_response_headers_policy" "radio_cors" {
  name    = "${terraform.workspace}-radio-cors"
  comment = "Public CORS for the live radio stream - no credentials, any origin."

  cors_config {
    access_control_allow_credentials = false

    access_control_allow_headers {
      items = ["*"]
    }

    access_control_allow_methods {
      items = ["GET", "HEAD", "OPTIONS"]
    }

    access_control_allow_origins {
      items = ["*"]
    }

    access_control_max_age_sec = 600

    origin_override = false
  }
}

resource "aws_cloudfront_distribution" "media" {
  enabled      = true
  http_version = "http2and3"
  aliases      = terraform.workspace == "dev" ? ["dev-cdn.${var.domain}"] : ["cdn.${var.domain}"]

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
    domain_name = var.media_bucket_domain_name
    origin_id   = var.media_bucket_id
    origin_path = "/production-ufb-media"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.media.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = var.media_bucket_id
    viewer_protocol_policy   = "redirect-to-https"
    compress                 = true
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.this.id
    # No inline TTL fields (conflict with cache_policy_id, same as /audio/*
    # below) - CloudFront silently ignores min/default/max_ttl whenever a
    # cache_policy_id is also set, so Managed-CachingOptimized's own TTLs
    # (1 day default) are what's actually governed this behavior all along.
    # The previous 604800/31536000 values here were dead code that only
    # produced a perpetual, unfixable plan diff.
    cache_policy_id = data.aws_cloudfront_cache_policy.this.id
  }

  # Audio previews — requires an authenticated-tier signed cookie (cf_preview_keygroup).
  # Must precede the /audio/* behavior below since CloudFront matches path patterns
  # in list order.
  ordered_cache_behavior {
    path_pattern               = "/audio/*/preview.mp3"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    target_origin_id           = var.media_bucket_id
    compress                   = true
    viewer_protocol_policy     = "redirect-to-https"
    trusted_key_groups         = [aws_cloudfront_key_group.cf_preview_keygroup.id]
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.this.id
    cache_policy_id            = data.aws_cloudfront_cache_policy.this.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.custom.id
  }

  # Offline download assets — a single opaque, already-AES-encrypted file per
  # track (no manifest, no segments, nothing to cache-bust), so this can use
  # a normal cache policy unlike the zero-TTL /audio/* behavior below. Must
  # precede /audio/* since CloudFront matches path patterns in list order.
  ordered_cache_behavior {
    path_pattern               = "/audio/*/download.enc"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    target_origin_id           = var.media_bucket_id
    compress                   = false
    viewer_protocol_policy     = "redirect-to-https"
    trusted_key_groups         = [aws_cloudfront_key_group.cf_download_keygroup.id]
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.this.id
    cache_policy_id            = data.aws_cloudfront_cache_policy.this.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.custom.id
  }

  # Audio — zero-TTL, signed cookies, no inline TTL fields (conflict with cache_policy_id)
  ordered_cache_behavior {
    path_pattern               = "/audio/*"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    target_origin_id           = var.media_bucket_id
    compress                   = true
    viewer_protocol_policy     = "redirect-to-https"
    trusted_key_groups         = [aws_cloudfront_key_group.cf_media_keygroup.id]
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.audio_cmaf_with_querystring.id
    cache_policy_id            = aws_cloudfront_cache_policy.audio_segments.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.custom.id

    # Rewrites a Cast-issued signed URL's query string onto every
    # segment/init URI inside an .m3u8 manifest so one signed request
    # authorizes the whole track, the same way a signed cookie implicitly
    # already does for browser playback (see ufb-iac's
    # cast-manifest-rewrite module). No-ops on every other request,
    # including all existing cookie-authorized browser traffic — it only
    # acts on a request that carries a query string.
    #
    # This has to be origin-request, not origin-response: Lambda@Edge
    # functions on a response event are never given the origin's response
    # body at all (confirmed by CloudFront itself — associating
    # include_body with an origin-response event was rejected outright:
    # "InvalidLambdaFunctionAssociation: The IncludeBody option can only
    # be used with viewer-request or origin-request events", and that
    # option only ever covers *request* bodies regardless). The Lambda
    # fetches the manifest itself from S3 and returns a complete response
    # object, short-circuiting the real origin fetch — no include_body
    # needed, since it never reads a request body either.
    lambda_function_association {
      event_type = "origin-request"
      lambda_arn = var.cast_manifest_rewrite_lambda_arn
    }
  }

  ordered_cache_behavior {
    path_pattern             = "/images/*"
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    target_origin_id         = var.media_bucket_id
    compress                 = true
    viewer_protocol_policy   = "redirect-to-https"
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.this.id
    cache_policy_id          = aws_cloudfront_cache_policy.images_immutable.id

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
    target_origin_id         = var.media_bucket_id
    compress                 = true
    viewer_protocol_policy   = "redirect-to-https"
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.this.id
    # No inline TTL fields - see default_cache_behavior above for why
    # (cache_policy_id already governs this; the previous 3600/86400 here
    # were dead code CloudFront silently ignored).
    cache_policy_id = data.aws_cloudfront_cache_policy.this.id
  }

  # Live radio manifests - public, unauthenticated, zero-TTL. Liquidsoap's
  # HLS output writes two: the master playlist (fixed name "playlist.m3u8")
  # and a per-stream variant playlist ("radio.m3u8", named after the stream
  # id in modules/radio) that actually lists the live segment window and
  # rewrites on every rotation - caching that one even briefly hands
  # listeners a stale segment list and stalls playback once they've worked
  # through it. The wildcard catches both. Must precede the /radio/*
  # segment behavior below since CloudFront matches path patterns in list
  # order and this is the more specific pattern. Appended last (rather than
  # wherever alongside the other /audio|images|static behaviors above) so
  # this addition doesn't shift any existing ordered_cache_behavior's list
  # position - CloudFront's provider diffs this list positionally, and an
  # unrelated position shift reads as those existing behaviors
  # changing/losing their lambda associations.
  ordered_cache_behavior {
    path_pattern               = "/radio/live/*.m3u8"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    target_origin_id           = var.media_bucket_id
    compress                   = true
    viewer_protocol_policy     = "redirect-to-https"
    cache_policy_id            = aws_cloudfront_cache_policy.radio_manifest.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.radio_cors.id
  }

  # Live radio HLS segments - public, unauthenticated. Each segment has a
  # unique filename (see modules/radio), so the standard optimized caching
  # policy is correct here rather than a bespoke one.
  ordered_cache_behavior {
    path_pattern               = "/radio/*"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    target_origin_id           = var.media_bucket_id
    compress                   = true
    viewer_protocol_policy     = "redirect-to-https"
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.this.id
    cache_policy_id            = data.aws_cloudfront_cache_policy.this.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.radio_cors.id
  }
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled      = true
  http_version = "http2and3"
  aliases      = ["production.${var.domain}"]

  viewer_certificate {
    acm_certificate_arn      = "arn:aws:acm:us-east-1:081077757258:certificate/e5eb1087-ba5d-4b03-8dd9-40a321e39f48"
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  origin {
    domain_name = var.alb_dns_name
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

# S3 bucket policies granting CloudFront OAI access

data "aws_iam_policy_document" "media" {
  statement {
    actions = ["s3:GetObject"]
    resources = [
      var.media_bucket_arn,
      "${var.media_bucket_arn}/*"
    ]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.media.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "media" {
  bucket = var.media_bucket_id
  policy = data.aws_iam_policy_document.media.json
}

data "aws_iam_policy_document" "frontend" {
  statement {
    actions = ["s3:GetObject"]
    resources = [
      var.frontend_bucket_arn,
      "${var.frontend_bucket_arn}/*"
    ]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.frontend.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = var.frontend_bucket_id
  policy = data.aws_iam_policy_document.frontend.json
}
