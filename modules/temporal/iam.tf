# ──────────────────────────────────────────────────────────────────────────────
# IAM
#
# Execution role  -> what the ECS *agent* may do on the task's behalf: pull the
#                    image, resolve secrets, write logs.
# Task role       -> what code *inside* the container may do. Temporal server
#                    needs nothing from AWS beyond ECS Exec, so it stays empty
#                    of data-plane permissions.
# ──────────────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    # Stops this role being assumable on behalf of a task in another account.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

# Read the RDS-managed master credentials. Scoped to the one secret ARN — the
# shared cluster policy grants a much broader `secret:*` wildcard, which this
# deliberately does not rely on.
resource "aws_iam_policy" "db_secret_read" {
  name        = "${var.name}-db-secret-read"
  description = "Read the RDS master credentials secret backing Temporal persistence"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "ReadDatabaseSecret"
          Effect = "Allow"
          Action = [
            "secretsmanager:GetSecretValue",
            "secretsmanager:DescribeSecret",
          ]
          Resource = [var.db_secret_arn]
        },
      ],
      # Only needed when the secret uses a customer-managed key; the
      # aws/secretsmanager default key needs no explicit grant.
      var.db_secret_kms_key_id == null ? [] : [
        {
          Sid      = "DecryptSecretKey"
          Effect   = "Allow"
          Action   = ["kms:Decrypt"]
          Resource = [var.db_secret_kms_key_id]
          Condition = {
            StringEquals = {
              "kms:ViaService" = "secretsmanager.${var.region}.amazonaws.com"
            }
          }
        },
      ],
    )
  })

  tags = var.tags
}

# ── Execution role, shared by the server roles and the one-off schema task ─────

resource "aws_iam_role" "task_exec" {
  name               = "${var.name}-task-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "task_exec_managed" {
  role       = aws_iam_role.task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "task_exec_shared" {
  role       = aws_iam_role.task_exec.name
  policy_arn = var.task_exec_policy_arn
}

resource "aws_iam_role_policy_attachment" "task_exec_db_secret" {
  role       = aws_iam_role.task_exec.name
  policy_arn = aws_iam_policy.db_secret_read.arn
}

# ── Task role for the server roles and admin-tools ────────────────────────────

resource "aws_iam_role" "server_task" {
  name               = "${var.name}-server-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = var.tags
}

# Required for `aws ecs execute-command`, which is how you get a tctl shell
# against a running cluster without exposing the frontend outside the VPC.
resource "aws_iam_role_policy" "server_task_exec_command" {
  count = var.enable_execute_command ? 1 : 0

  name = "ecs-exec"
  role = aws_iam_role.server_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMMessagesForECSExec"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ]
        Resource = "*"
      },
    ]
  })
}

# ── Extra permissions for the Python worker's activities ──────────────────────

resource "aws_iam_policy" "worker_secrets" {
  count = length(var.worker_secret_arns) > 0 ? 1 : 0

  name        = "${var.name}-worker-secrets"
  description = "Secrets the Temporal worker's activities may read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadWorkerSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = var.worker_secret_arns
      },
    ]
  })

  tags = var.tags
}
