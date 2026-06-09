resource "aws_iam_policy" "ecs_airflow_secrets_policy" {
  name        = "ecs-airflow-secrets-policy"
  description = "Allow airflow ECS task to read secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:eu-west-2:081077757258:secret:prod/ufb/airflow*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "*"
      }
    ]
  })
}
