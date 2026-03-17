resource "aws_iam_policy" "search_ecs_task_exec_policy" {
  name        = "${terraform.workspace}-search-ecs-task-exec-secrets-policy"
  description = "Allow ECS task execution role to pull images, write logs, and get secrets from Secrets Manager"

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
          "${var.secret_prefix}:*"
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
