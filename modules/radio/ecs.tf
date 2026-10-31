module "radio_task_definition" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name        = var.name
  cluster_arn = var.ecs_cluster_arn

  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  # See modules/recommendations/ecs.tf (and modules/search/ecs.tf) for the
  # same pattern: ufb-radio's CircleCI pipeline deploys by pinning the
  # service to a SHA-tagged image via aws-ecs/update_service, bypassing
  # Terraform. Without these, the next apply would push the service back
  # onto whatever task definition this config describes (image_uri's
  # literal ":latest"), undoing that deploy.
  ignore_task_definition_changes = true
  skip_destroy                   = true

  # Audio-only encoding (no live DJ input yet, no video) - smallest valid
  # Fargate size is enough and keeps this near-free to run.
  cpu    = 256
  memory = 512

  # No live DJ input in v1 and no listeners connect to this task directly
  # (they're served the HLS output via CloudFront/S3 - see modules/cdn's
  # /radio/* behavior), so there's nothing to broadcast until someone turns
  # it on. This is a brand new service with no real-world state to protect,
  # so - unlike modules/temporal/server.tf - desired_count doesn't need
  # ignore_changes; just start at zero.
  desired_count = 0

  # This is a single live broadcast source, not a horizontally scalable
  # service - two replicas would both write conflicting output to the same
  # S3 prefix. The module defaults autoscaling on (1-10 tasks); turn it off.
  enable_autoscaling = false

  container_definitions = {
    radio = {
      cpu                                    = 256
      memory                                 = 512
      essential                              = true
      image                                  = var.image_uri
      user                                   = "0"
      readonlyRootFilesystem                 = false
      cloudwatch_log_group_retention_in_days = 1

      environment = [
        {
          name  = "MEDIA_BUCKET_NAME"
          value = var.media_bucket_name
        },
        {
          # The bucket's real content lives under an internal
          # production-ufb-media/ folder (matching the bucket's own name -
          # see modules/storage) - CloudFront's media origin_path expects
          # that prefix, so objects placed directly at radio/* 404 via
          # CloudFront even though they exist in the bucket.
          name  = "RADIO_PLAYLIST_PREFIX"
          value = "production-ufb-media/radio/playlist/"
        },
        {
          name  = "RADIO_OUTPUT_PREFIX"
          value = "production-ufb-media/radio/live/"
        },
      ]
    }
  }

  subnet_ids = var.private_subnets

  # Nothing connects to this task directly - no live DJ input, no internal
  # caller - so there's no ingress to open at all.
  security_group_ingress_rules = {}

  security_group_egress_rules = {
    all = {
      type        = "egress"
      from_port   = 0
      to_port     = 65535
      protocol    = "-1"
      description = "Allow all outbound (ECR pull, S3 sync, CloudWatch logs)"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  create_task_exec_iam_role = true
  task_exec_iam_role_name   = "ecs-radio-task-exec-role"

  tasks_iam_role_statements = [
    {
      effect    = "Allow"
      actions   = ["s3:ListBucket"]
      resources = [var.media_bucket_arn]
    },
    {
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
      ]
      resources = ["${var.media_bucket_arn}/production-ufb-media/radio/*"]
    }
  ]
}
