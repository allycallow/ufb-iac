resource "aws_iam_role" "s3_rds" {
  name = "${local.name}-RDSRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "rds.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_access_policy" {
  name = "s3-access"
  role = aws_iam_role.s3_rds.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:*",
          "s3-object-lambda:*"
        ],
        Resource = "*"
      }
    ]
  })
}

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

resource "aws_iam_policy" "s3_export_policy" {
  name        = "AirflowS3ExportPolicy"
  description = "Allows Airflow to upload CSVs to the recommendations bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::ufb-db-exports/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::ufb-db-exports"
      }
    ]
  })
}
