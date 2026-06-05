resource "aws_iam_policy" "tempo_s3_access" {
  name        = "TempoS3AccessPolicy"
  description = "Allows Grafana Tempo on ECS to manage its storage bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [aws_s3_bucket.tempo_traces.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = ["${aws_s3_bucket.tempo_traces.arn}/*"]
      }
    ]
  })
}
