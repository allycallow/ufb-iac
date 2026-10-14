# The shared cluster task-exec policy (var.task_exec_policy_arn) only grants
# Secrets Manager access to the backend's own secret prefix, so each module
# that needs other secrets reads them through its own scoped policy — same
# pattern as modules/temporal/iam.tf.
resource "aws_iam_policy" "secret_read" {
  # name_prefix, not name: an IAM policy's `description` is immutable, so any
  # edit to it forces a replace. A fixed name then collides with itself for
  # the brief window both the old and new policy exist — AWS rejects two IAM
  # policies with the same name. name_prefix + create_before_destroy avoids
  # that, same reasoning as aws_db_parameter_group.default in modules/database.
  name_prefix = "${var.name}-secret-read-"
  description = "Read the DB credentials Unleash needs at boot"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadUnleashSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = [
          aws_secretsmanager_secret.db.arn,
        ]
      },
    ]
  })

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}
