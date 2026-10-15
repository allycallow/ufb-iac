# Dedicated CMK so a leaked bucket-read permission isn't enough on its own -
# the reader also needs kms:Decrypt on this specific key, which only the
# ddex-ingest, audio-processing, and track-metadata task roles (and account
# admins, via the standard "root can delegate through IAM" statement) hold.
# audio-processing/track-metadata were added so DDEX-delivered audio can be
# encoded/analyzed directly from this bucket (DdexDeliveryWorkflow starts
# TrackIngestionSagaWorkflow with this bucket/key once a Track exists) -
# without them, those ECS tasks would get AccessDenied reading a delivery
# object even though the S3 bucket policy's VPC-endpoint check passes (both
# run in the same private subnets as ddex-ingest, behind the same S3 Gateway
# endpoint).
resource "aws_kms_key" "deliveries" {
  description             = "Encrypts DDEX delivery assets at rest in ${var.name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowDdexIngestTaskDecrypt"
        Effect = "Allow"
        Principal = {
          AWS = module.ddex_ingest_task_definition.tasks_iam_role_arn
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowAudioPipelineTaskDecrypt"
        Effect = "Allow"
        Principal = {
          AWS = [
            var.audio_processing_task_role_arn,
            var.track_metadata_task_role_arn,
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name}-cmk"
  })
}

resource "aws_kms_alias" "deliveries" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.deliveries.key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "deliveries" {
  bucket = aws_s3_bucket.deliveries.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.deliveries.arn
    }
    bucket_key_enabled = true
  }
}

# Scoped to reads only - partner uploads (PutObject) still work from outside
# the VPC, since no partner has direct AWS credentials yet anyway (see the
# per-partner IAM scoping ticket). This specifically blocks exfiltration: a
# leaked task-role credential, or a compromised principal anywhere else in
# the account, cannot read delivery assets from outside this VPC. The
# operational tradeoff is that debugging a delivery (e.g. inspecting an
# object by hand) has to go through something running inside the VPC - a
# Teleport-fronted exec into an ECS task, not a laptop `aws s3 cp`.
resource "aws_s3_bucket_policy" "deliveries" {
  bucket = aws_s3_bucket.deliveries.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.deliveries.arn,
          "${aws_s3_bucket.deliveries.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid       = "DenyReadsOutsideVpc"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:GetObjectTagging",
          "s3:GetObjectVersion",
        ]
        Resource = "${aws_s3_bucket.deliveries.arn}/*"
        Condition = {
          StringNotEquals = {
            "aws:sourceVpce" = var.s3_vpc_endpoint_id
          }
        }
      }
    ]
  })
}
