# The Lambda is deployed and managed outside this repo; we only need its
# ARN to wire up the nightly schedule below.
data "aws_lambda_function" "ecs_stop_task" {
  function_name = "ufb-ecs-stop-task"
}

module "eventbridge" {
  source   = "terraform-aws-modules/eventbridge/aws"
  bus_name = local.name
  rules    = {}
  targets  = {}

  # EventBridge Scheduler (not classic cron rules) so the 22:00 fire time
  # stays fixed to UK local time across the BST/GMT transition.
  attach_lambda_policy = true
  lambda_target_arns   = [data.aws_lambda_function.ecs_stop_task.arn]

  # The Lambda itself scales all ECS services to 0 and stops the RDS
  # instance (DB_INSTANCE_IDENTIFIER env var on the function), so a single
  # nightly invocation covers both — no separate RDS scheduler target needed.
  #
  # It doesn't scale ECS or start RDS back up in the morning — that's a
  # manual step for now.
  schedules = {
    ecs_stop_task_nightly = {
      description         = "Nightly stop of ECS tasks and RDS via ufb-ecs-stop-task"
      schedule_expression = "cron(0 22 * * ? *)"
      timezone            = "Europe/London"
      arn                 = data.aws_lambda_function.ecs_stop_task.arn
    }
  }
}

output "eventbridge_bus_name" {
  value = module.eventbridge.eventbridge_bus_name
}
