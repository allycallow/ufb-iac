resource "aws_iam_policy" "track_metadata_processing_ecs_task_exec_policy" {
  name        = "${terraform.workspace}-tm-ecs-task-exec"
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
