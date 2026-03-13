resource "aws_cloudwatch_log_group" "airflow" {
  name              = "/ecs/${local.name}-airflow"
  retention_in_days = 1
}
