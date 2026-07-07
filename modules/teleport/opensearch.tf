resource "aws_iam_role" "opensearch_access" {
  name = "${var.name}-teleport-opensearch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = module.teleport_task_definition.tasks_iam_role_arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "opensearch_access" {
  name = "opensearch-access"
  role = aws_iam_role.opensearch_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "OpenSearchAccess"
        Effect = "Allow"
        Action = [
          "es:ESHttpGet",
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpDelete",
          "es:ESHttpHead"
        ]
        Resource = "${var.opensearch_domain_arn}/*"
      }
    ]
  })
}
