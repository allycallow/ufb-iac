module "airflow_task_definition" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name        = var.name
  cluster_arn = var.ecs_cluster_arn

  # Required whenever capacity_provider_strategy changes: ECS cannot move tasks
  # between capacity providers without a new deployment, and the module asserts
  # this rather than letting the change apply silently and do nothing.
  force_new_deployment = var.use_spot

  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  cpu    = 2048
  memory = 8192

  # ── Fargate Spot ────────────────────────────────────────────────────────────
  #
  # At 2 vCPU / 8 GB ARM64 this is the most expensive service in the cluster:
  # ~$78/month on-demand, ~$23 on Spot.
  #
  # Both providers are listed rather than Spot alone. With a single task the
  # 99:1 weighting sends effectively every placement to Spot, but keeping
  # FARGATE in the strategy leaves a fallback when an ARM64 Spot pool is
  # exhausted — Spot-only would simply fail to place and leave Airflow down.
  #
  # Note this service previously ran on-demand by accident, not by choice: the
  # shared service module defaults `launch_type = "FARGATE"`, and an explicit
  # launch_type makes ECS ignore the cluster's default capacity provider
  # strategy entirely.
  capacity_provider_strategy = var.use_spot ? {
    spot = {
      capacity_provider = "FARGATE_SPOT"
      weight            = 99
      base              = 0
    }
    on_demand = {
      capacity_provider = "FARGATE"
      weight            = 1
      base              = 0
    }
    } : {
    on_demand = {
      capacity_provider = "FARGATE"
      weight            = 1
      base              = 0
    }
  }

  container_definitions = {
    airflow = {
      cpu                                    = 2048
      memory                                 = 4096
      essential                              = true
      image                                  = var.image_uri
      user                                   = "0"
      readonlyRootFilesystem                 = false
      cloudwatch_log_group_retention_in_days = 1

      portMappings = [
        {
          name          = "airflow"
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "AIRFLOW__CORE__EXECUTOR"
          value = "LocalExecutor"
        },
        {
          name  = "AIRFLOW__CORE__LOAD_EXAMPLES"
          value = "False"
        },
        {
          name  = "AIRFLOW__API__BASE_URL"
          value = "https://airflow.upfrontbeats.com"
        },
        {
          name  = "AIRFLOW__WEBSERVER__BASE_URL"
          value = "https://airflow.upfrontbeats.com"
        },
        {
          name  = "AIRFLOW__CORE__EXECUTION_API_SERVER_URL"
          value = "http://localhost:8080/execution/"
        },
        {
          name  = "AIRFLOW__API__EXPOSE_CONFIG"
          value = "False"
        },
        {
          name  = "AIRFLOW__AWS_AUTH_MANAGER__SAML_METADATA_URL"
          value = "https://portal.sso.eu-west-2.amazonaws.com/saml/metadata/MDgxMDc3NzU3MjU4X2lucy03NTM1N2QxZTNmNjE3MjBl"
        },
        {
          name  = "AIRFLOW__CORE__AUTH_MANAGER"
          value = "airflow.providers.amazon.aws.auth_manager.aws_auth_manager.AwsAuthManager"
        },
        {
          name  = "AIRFLOW__AWS_AUTH_MANAGER__REGION_NAME"
          value = "eu-west-2"
        },
        {
          name  = "AIRFLOW__CORE__ALLOWED_DESERIALIZATION_CLASSES"
          value = "google.genai.types.*"
        },
        {
          name  = "BACKEND_API_ENDPOINT"
          value = "https://new-admin.upfrontbeats.com/api"
        },
        {
          name  = "AIRFLOW__METRICS__STATSD_ON"
          value = "True"
        },
        {
          name  = "AIRFLOW__METRICS__STATSD_HOST"
          value = "localhost"
        },
        {
          name  = "AIRFLOW__METRICS__STATSD_PORT"
          value = "9125"
        },
        {
          name  = "AIRFLOW__METRICS__STATSD_PREFIX"
          value = "airflow"
        }
      ]

      secrets = [
        {
          name      = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN"
          valueFrom = "arn:aws:secretsmanager:eu-west-2:${data.aws_caller_identity.current.account_id}:secret:prod/ufb/airflow-JDJfSg:AIRFLOW__DATABASE__SQL_ALCHEMY_CONN::"
        },
        {
          name      = "AIRFLOW__CORE__FERNET_KEY"
          valueFrom = "arn:aws:secretsmanager:eu-west-2:${data.aws_caller_identity.current.account_id}:secret:prod/ufb/airflow-JDJfSg:AIRFLOW__CORE__FERNET_KEY::"
        },
        {
          name      = "AIRFLOW__API__SECRET_KEY"
          valueFrom = "arn:aws:secretsmanager:eu-west-2:${data.aws_caller_identity.current.account_id}:secret:prod/ufb/airflow-JDJfSg:AIRFLOW__API__SECRET_KEY::"
        },
        {
          name      = "GEMINI_API_KEY"
          valueFrom = "arn:aws:secretsmanager:eu-west-2:${data.aws_caller_identity.current.account_id}:secret:prod/ufb/airflow-JDJfSg:GEMINI_API_KEY::"
        },
        {
          name      = "BACKEND_API_KEY"
          valueFrom = "arn:aws:secretsmanager:eu-west-2:${data.aws_caller_identity.current.account_id}:secret:prod/ufb/airflow-JDJfSg:BACKEND_API_KEY::"
        },
        {
          # Overrides the UI-managed "prod-ufb-db" connection. Airflow's
          # env-var connection lookup uppercases conn_id as-is (no dash-to-
          # underscore substitution), so the name must keep the dashes.
          name      = "AIRFLOW_CONN_PROD-UFB-DB"
          valueFrom = "arn:aws:secretsmanager:eu-west-2:${data.aws_caller_identity.current.account_id}:secret:prod/ufb/airflow-JDJfSg:AIRFLOW_CONN_PROD-UFB-DB::"
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.name}"
          "awslogs-region"        = "eu-west-2"
          "awslogs-stream-prefix" = "airflow"
        }
      }
    }

    statsd-exporter = {
      memory                                 = 256
      image                                  = "prom/statsd-exporter:v0.27.1"
      essential                              = false
      readonlyRootFilesystem                 = false
      cloudwatch_log_group_retention_in_days = 1
      portMappings = [
        {
          name          = "statsd-exporter"
          containerPort = 9102
          hostPort      = 9102
          protocol      = "tcp"
        }
      ]
      enable_cloudwatch_logging = true
    }
  }

  subnet_ids                        = var.private_subnets
  autoscaling_max_capacity          = 1
  autoscaling_min_capacity          = 1
  health_check_grace_period_seconds = 120

  load_balancer = {
    service = {
      target_group_arn = var.alb_target_group_arn
      container_name   = "airflow"
      container_port   = 8080
    }
  }

  service_connect_configuration = {
    enabled   = true
    namespace = var.service_connect_namespace
    service = [{
      port_name      = "statsd-exporter"
      discovery_name = "airflow-statsd-sc"
      client_alias = {
        dns_name = "airflow-statsd"
        port     = 9102
      }
    }]
  }

  security_group_ingress_rules = {
    alb_ingress_8080 = {
      type                         = "ingress"
      from_port                    = 8080
      to_port                      = 8080
      protocol                     = "tcp"
      description                  = "Allow traffic from ALB"
      referenced_security_group_id = var.alb_security_group_id
    }

    monitoring_ingress_9102 = {
      type                         = "ingress"
      from_port                    = 9102
      to_port                      = 9102
      protocol                     = "tcp"
      description                  = "Allow Prometheus to scrape StatsD exporter"
      referenced_security_group_id = var.monitoring_security_group_id
    }
  }

  security_group_egress_rules = {
    all = {
      type        = "egress"
      from_port   = 0
      to_port     = 65535
      protocol    = "-1"
      description = "Allow all outbound"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  create_task_exec_iam_role = true
  task_exec_iam_role_name   = "ecs-airflow-task-exec-role"

  tasks_iam_role_statements = [
    {
      effect = "Allow"
      actions = [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:GetObject"
      ]
      resources = [
        "arn:aws:s3:::ufb-db-exports/*",
        "arn:aws:s3:::prod-recommendations-formatted/*",
        "arn:aws:s3:::prod-recommendations-processed/*",
        "arn:aws:s3:::ufb-prod-outputs/*"
      ]
    },
    {
      effect = "Allow"
      actions = [
        "s3:ListBucket"
      ]
      resources = [
        "arn:aws:s3:::ufb-db-exports",
        "arn:aws:s3:::prod-recommendations-formatted",
        "arn:aws:s3:::prod-recommendations-processed",
        "arn:aws:s3:::ufb-prod-outputs"
      ]
    },
    {
      effect = "Allow"
      actions = [
        "sagemaker:*",
        "logs:*"
      ]
      resources = ["*"]
    },

    # Allow SageMaker jobs
    {
      effect  = "Allow"
      actions = ["iam:PassRole"]
      resources = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/TrainAndBatchTransform-SageMakerAPIExecutionRole"
      ]
      condition = [{
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["sagemaker.amazonaws.com"]
      }]
    },

    # DynamoDB permissions
    {
      effect = "Allow"
      actions = [
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:BatchWriteItem",
        "dynamodb:Query"
      ]
      resources = [
        "arn:aws:dynamodb:eu-west-2:${data.aws_caller_identity.current.account_id}:table/production-ufb-recommendations"
      ]
    },

    # IAM Identity Center permissions for AwsAuthManager
    {
      effect = "Allow"
      actions = [
        "sso:DescribeRegisteredRegions",
        "sso:ListApplicationAssignments",
        "identitystore:DescribeUser",
        "identitystore:DescribeGroup",
        "identitystore:ListGroupMembershipsForMember"
      ]
      resources = ["*"]
    }
  ]

  task_exec_iam_role_policies = {
    exec_policy     = var.task_exec_policy_arn
    airflow_secrets = aws_iam_policy.ecs_airflow_secrets_policy.arn
  }

  tags = var.tags
}
