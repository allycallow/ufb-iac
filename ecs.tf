resource "aws_iam_policy" "ecs_task_exec_policy" {
  name        = "ecs-task-exec-secrets-policy"
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
          "${local.secret_prefix}*"
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
      {
        Sid    = "SSMParameterAccess"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParameterHistory"
        ]
        Resource = [
          aws_ssm_parameter.media_private_key.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_task_exec_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_task_exec_policy.arn
}

module "ecs_cluster" {
  source = "terraform-aws-modules/ecs/aws//modules/cluster"

  name = local.name

  task_exec_secret_arns = [
    "arn:aws:secretsmanager:${local.region}:${data.aws_caller_identity.current.account_id}:secret:*"
  ]

  cluster_capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 50
        base   = 20
      }
    }
    FARGATE_SPOT = {
      default_capacity_provider_strategy = {
        weight = 50
      }
    }
  }
}


module "backend_task_definition" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name                 = "${local.name}-backend"
  cluster_arn          = module.ecs_cluster.arn
  force_new_deployment = false

  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = {
    backend = {
      cpu                    = 1024
      memory                 = 2048
      essential              = true
      image                  = "${aws_ecr_repository.repos["backend"].repository_url}:latest"
      user                   = "0"
      readonlyRootFilesystem = false

      portMappings = [
        {
          name          = "backend"
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          "name" : "ENV_NAME",
          "value" : "production"
        },
        {
          "name" : "DB_HOST",
          "value" : split(":", module.db.db_instance_endpoint)[0]
        },
        {
          "name" : "MEDIA_BUCKET_NAME",
          "value" : aws_s3_bucket.media.bucket
        },
        {
          "name" : "AWS_S3_CUSTOM_DOMAIN",
          "value" : "cdn.upfrontbeats.com"
        },
        {
          "name" : "AWS_S3_ENDPOINT_URL",
          "value" : "https://${aws_s3_bucket.media.bucket}.s3.eu-west-2.amazonaws.com"
        },
        {
          "name" : "SENTRY_DSN",
          "value" : "https://b3aaaae1af6c0a1c37c025a3929138ff@us.sentry.io/4506688829521920"
        },
        {
          "name" : "USERPOOL_ID",
          "value" : aws_cognito_user_pool.pool.id
        },
        {
          "name" : "APP_CLIENT_ID",
          "value" : aws_cognito_user_pool_client.client.id
        },
        {
          "name" : "CF_MEDIA_KEY_ID",
          "value" : aws_cloudfront_public_key.cf_media_key.id
        },
        {
          "name" : "EVENT_BUS_NAME",
          "value" : module.eventbridge.eventbridge_bus_name
        },
        {
          "name" : "RECOMMENDATIONS_ENDPOINT",
          "value" : "https://recommendations.upfrontbeats.com"
        },
        {
          "name" : "REDIS_HOST",
          "value" : "${aws_elasticache_cluster.redis.cache_nodes[0].address}"
        },
        {
          "name" : "SEARCH_ENDPOINT",
          "value" : "https://search.upfrontbeats.com/api"
        },
        {
          "name" : "RUDDER_STACK_DATA_PLANE_URL",
          "value" : "https://upfrontbeajzbi.dataplane.rudderstack.com"
        },
      ]

      secrets = [
        {
          "name" : "DB_USERNAME",
          "valueFrom" : "${local.secret_prefix}:db_user::"
        },
        {
          "name" : "DB_PASSWORD",
          "valueFrom" : "${local.secret_prefix}:db_password::"
        },
        {
          "name" : "RUDDER_STACK_WRITE_KEY",
          "valueFrom" : "${local.secret_prefix}:rudder_stack_write_key::"
        },
        {
          "name" : "RECOMMENDATIONS_API_KEY",
          "valueFrom" : "${local.secret_prefix}:recommendations_api_key::"
        },
        {
          "name" : "BETTER_STACK_TOKEN",
          "valueFrom" : "${local.secret_prefix}:better_stack_token::"
        },
        {
          "name" : "API_KEY",
          "valueFrom" : "${local.secret_prefix}:API_KEY::"
        },
        {
          "name" : "MEDIA_PRIVATE_KEY_VALUE",
          "valueFrom" : aws_ssm_parameter.media_private_key.arn
        },
        {
          "name" : "STRIPE_API_KEY",
          "valueFrom" : "${local.secret_prefix}:stripe_api_key::"
        },
        {
          "name" : "KNOCK_API_KEY",
          "valueFrom" : "${local.secret_prefix}:knock_api_key::"
        },
        {
          "name" : "SEARCH_API_KEY",
          "valueFrom" : "${local.secret_prefix}:SEARCH_API_KEY::"
        },
      ]
    }
  }

  subnet_ids               = module.vpc.private_subnets
  autoscaling_max_capacity = 2

  load_balancer = {
    service = {
      target_group_arn = module.alb.target_groups["backend"].arn
      container_name   = "backend"
      container_port   = 8000
    }
  }

  security_group_ingress_rules = {
    alb_ingress_8000 = {
      type                         = "ingress"
      from_port                    = 8000
      to_port                      = 8000
      protocol                     = "tcp"
      description                  = "Allow traffic from ALB"
      referenced_security_group_id = module.alb.security_group_id
    }
  }


  security_group_egress_rules = {
    all = {
      type        = "egress"
      from_port   = 0
      to_port     = 65535
      protocol    = "-1"
      description = "Allow traffic from anywhere"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  create_task_exec_iam_role = true
  task_exec_iam_role_name   = "ecs-ufb-backend-task-exec-role"
  task_exec_iam_role_policies = {
    exec_policy = aws_iam_policy.ecs_task_exec_policy.arn
  }


  tasks_iam_role_statements = [
    {
      actions = [
        "events:PutEvents"
      ]
      effect    = "Allow"
      resources = [module.eventbridge.eventbridge_bus_arn]
    },
    {
      actions = [
        "s3:PutObject"
      ]
      effect = "Allow"
      resources = [
        aws_s3_bucket.media.arn,
        "${aws_s3_bucket.media.arn}/*"
      ]
    },
    {
      actions = [
        "secretsmanager:GetSecretValue"
      ]
      effect = "Allow"
      resources = [
        "arn:aws:secretsmanager:eu-west-2:${data.aws_caller_identity.current.account_id}:secret:prod/ufb/backend-NKRahZ*"
      ]
    },
    {
      actions = ["cognito-idp:AdminGetUser"]
      effect  = "Allow"
      resources = [
        aws_cognito_user_pool.pool.arn
      ]
    },
    {
      actions = ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:GetItem"]
      effect  = "Allow"
      resources = [
        "arn:aws:dynamodb:eu-west-2:${data.aws_caller_identity.current.account_id}:table/production-ufb-recently-played"
      ]
    }
  ]
}

module "frontend_task_definition" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name                 = "${local.name}-frontend"
  cluster_arn          = module.ecs_cluster.arn
  force_new_deployment = false

  cpu    = 512
  memory = 1024

  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = {
    frontend = {
      cpu                    = 512
      memory                 = 1024
      essential              = true
      image                  = "${aws_ecr_repository.repos["frontend"].repository_url}:latest"
      user                   = "0"
      readonlyRootFilesystem = false

      portMappings = [
        {
          name          = "frontend"
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          "name" : "AMPLIFY_APP_ORIGIN",
          "value" : "https://production.upfrontbeats.com"
        },
        {
          "name" : "REACT_APP_ENDPOINT",
          "value" : "https://new-admin.upfrontbeats.com/graphql"
        },
      ]

      secrets = []
    }
  }

  subnet_ids               = module.vpc.private_subnets
  autoscaling_max_capacity = 2

  load_balancer = {
    service = {
      target_group_arn = module.alb.target_groups["frontend"].arn
      container_name   = "frontend"
      container_port   = 3000
    }
  }

  security_group_ingress_rules = {
    alb_ingress_3000 = {
      type                         = "ingress"
      from_port                    = 3000
      to_port                      = 3000
      protocol                     = "tcp"
      description                  = "Allow traffic from ALB"
      referenced_security_group_id = module.alb.security_group_id
    }
  }


  security_group_egress_rules = {
    all = {
      type        = "egress"
      from_port   = 0
      to_port     = 65535
      protocol    = "-1"
      description = "Allow traffic from anywhere"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  create_task_exec_iam_role = true
  task_exec_iam_role_name   = "ecs-ufb-frontend-task-exec-role"
  task_exec_iam_role_policies = {
    exec_policy = aws_iam_policy.ecs_task_exec_policy.arn
  }
}

module "airflow_task_definition" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name                 = "${local.name}-airflow"
  cluster_arn          = module.ecs_cluster.arn
  force_new_deployment = false


  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  cpu    = 2048
  memory = 8192

  container_definitions = {
    airflow = {
      cpu                    = 2048
      memory                 = 4096
      essential              = true
      image                  = "${aws_ecr_repository.repos["airflow"].repository_url}:latest"
      user                   = "0"
      readonlyRootFilesystem = false

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
          name  = "AIRFLOW__API__EXPOSE_CONFIG"
          value = "False"
        },
        # {
        #   name  = "AIRFLOW__AWS_AUTH_MANAGER__SAML_METADATA_URL"
        #   value = "https://portal.sso.eu-west-2.amazonaws.com/saml/metadata/MDgxMDc3NzU3MjU4X2lucy03NTM1N2QxZTNmNjE3MjBl"
        # },
        # {
        #   name  = "AIRFLOW__CORE__AUTH_MANAGER"
        #   value = "airflow.providers.amazon.aws.auth_manager.aws_auth_manager.AwsAuthManager"
        # },
        # {
        #   name  = "AIRFLOW__AWS_AUTH_MANAGER__REGION_NAME"
        #   value = "eu-west-2"
        # },
        {
          name  = "AIRFLOW__CORE__ALLOWED_DESERIALIZATION_CLASSES"
          value = "google.genai.types.*"
        },
        {
          name  = "_AIRFLOW_WWW_USER_CREATE"
          value = "true"
        },
        {
          name  = "AIRFLOW__CORE__AUTH_MANAGER"
          value = "airflow.providers.fab.auth_manager.fab_auth_manager.FabAuthManager"
        },
        {
          name  = "BACKEND_API_ENDPOINT"
          value = "https://new-admin.upfrontbeats.com/api"
        },
        {
          name  = "_AIRFLOW_WWW_USER_USERNAME"
          value = "admin"
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
          name      = "_AIRFLOW_WWW_USER_PASSWORD"
          valueFrom = "arn:aws:secretsmanager:eu-west-2:${data.aws_caller_identity.current.account_id}:secret:prod/ufb/airflow-JDJfSg:_AIRFLOW_WWW_USER_PASSWORD::"
        },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${local.name}-airflow"
          "awslogs-region"        = "eu-west-2"
          "awslogs-stream-prefix" = "airflow"
        }
      }
    }
  }

  subnet_ids                        = module.vpc.private_subnets
  autoscaling_max_capacity          = 1
  autoscaling_min_capacity          = 1
  health_check_grace_period_seconds = 120

  load_balancer = {
    service = {
      target_group_arn = module.alb.target_groups["airflow"].arn
      container_name   = "airflow"
      container_port   = 8080
    }
  }

  security_group_ingress_rules = {
    alb_ingress_8080 = {
      type                         = "ingress"
      from_port                    = 8080
      to_port                      = 8080
      protocol                     = "tcp"
      description                  = "Allow traffic from ALB"
      referenced_security_group_id = module.alb.security_group_id
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

    # Allow Airflow to run ECS tasks
    {
      effect = "Allow"
      actions = [
        "ecs:RunTask",
        "ecs:DescribeTasks"
      ]
      resources = [
        "arn:aws:ecs:eu-west-2:${data.aws_caller_identity.current.account_id}:task-definition/production-audio-processing:*",
        "arn:aws:ecs:eu-west-2:${data.aws_caller_identity.current.account_id}:task-definition/production-ufb-tm-processing:*",
        "arn:aws:ecs:eu-west-2:${data.aws_caller_identity.current.account_id}:task/production-ufb/*",
      ]
    },

    # Allow passing the TASK ROLE
    {
      effect  = "Allow"
      actions = ["iam:PassRole", "ecs:DescribeTasks"]
      resources = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecs-audio-processing-task-exec-role-*",
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecs-tm-task-exec-role-*",
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/production-audio-processing-tasks-*",
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/production-ufb-tm-processing-tasks-*"
      ]
      condition = [{
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["ecs-tasks.amazonaws.com"]
      }]
    },

    # Allow passing the TRACK METADATA PROCESSING TASK ROLE
    {
      effect  = "Allow"
      actions = ["iam:PassRole"]
      resources = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/production-ufb-tm-processing-tasks-*"
      ]
      condition = [{
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["ecs-tasks.amazonaws.com"]
      }]
    },

    # DynamoDB permissions
    {
      effect = "Allow"
      actions = [
        "dynamodb:PutItem",
        "dynamodb:UpdateItem"
      ]
      resources = [
        "arn:aws:dynamodb:eu-west-2:${data.aws_caller_identity.current.account_id}:table/production-ufb-recommendations"
      ]
    },

    # SQS permissions
    {
      effect = "Allow"
      actions = [
        "sqs:GetMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:ReceiveMessage"
      ]
      resources = [
        module.audio_processing.queue_arn,
        module.audio_processing.dlq_arn
      ]
    }
  ]

  task_exec_iam_role_name = "ecs-airflow-task-exec-role"
  task_exec_iam_role_policies = {
    exec_policy     = aws_iam_policy.ecs_task_exec_policy.arn
    airflow_secrets = aws_iam_policy.ecs_airflow_secrets_policy.arn
  }
}

output "cluster_name" {
  value = local.name
}
