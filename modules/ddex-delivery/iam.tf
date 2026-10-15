resource "aws_sqs_queue_policy" "allow_s3" {
  queue_url = aws_sqs_queue.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.main.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.deliveries.arn
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "ddex_ingest_ecs_task_exec_policy" {
  name_prefix = "${terraform.workspace}-ddex-ingest-ecs-task-exec-secrets-"
  description = "Allow ECS task execution role to pull images, write logs, and get secrets from Secrets Manager"

  lifecycle {
    create_before_destroy = true
  }

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "*"
        ]
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
      },
    ]
  })
}
