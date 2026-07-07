module "backend_task_definition" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name                 = var.name
  cluster_arn          = var.ecs_cluster_arn
  force_new_deployment = true

  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = {
    backend = {
      cpu                    = 1024
      memory                 = 2048
      essential              = true
      image                  = var.image_uri
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
          "value" : var.db_endpoint
        },
        {
          "name" : "MEDIA_BUCKET_NAME",
          "value" : var.media_bucket_name
        },
        {
          "name" : "AWS_S3_CUSTOM_DOMAIN",
          "value" : "cdn.upfrontbeats.com"
        },
        {
          "name" : "AWS_S3_ENDPOINT_URL",
          "value" : "https://${var.media_bucket_name}.s3.eu-west-2.amazonaws.com"
        },
        {
          "name" : "SENTRY_DSN",
          "value" : "https://b3aaaae1af6c0a1c37c025a3929138ff@us.sentry.io/4506688829521920"
        },
        {
          "name" : "USERPOOL_ID",
          "value" : var.cognito_user_pool_id
        },
        {
          "name" : "APP_CLIENT_ID",
          "value" : var.cognito_app_client_id
        },
        {
          "name" : "CF_MEDIA_KEY_ID",
          "value" : var.cf_media_key_id
        },
        {
          "name" : "EVENT_BUS_NAME",
          "value" : var.event_bus_name
        },
        {
          "name" : "RECOMMENDATIONS_ENDPOINT",
          "value" : "http://recommendations:8000"
        },
        {
          "name" : "SEARCH_ENDPOINT",
          "value" : "http://search:8000/api"
        },
        {
          "name" : "RUDDER_STACK_DATA_PLANE_URL",
          "value" : "https://upfrontbeajzbi.dataplane.rudderstack.com"
        },
        {
          "name" : "REDIS_HOST",
          "value" : var.redis_host
        },
        {
          "name" : "REDIS_TLS",
          "value" : "true"
        },
        {
          "name" : "OTEL_EXPORTER_OTLP_ENDPOINT",
          "value" : "http://tempo:4317"
        },
        {
          "name" : "OTEL_EXPORTER_OTLP_TIMEOUT",
          "value" : "30000"
        }
      ]

      secrets = [
        {
          "name" : "DB_USERNAME",
          "valueFrom" : "${var.secret_prefix}:db_user::"
        },
        {
          "name" : "DB_PASSWORD",
          "valueFrom" : "${var.secret_prefix}:db_password::"
        },
        {
          "name" : "RUDDER_STACK_WRITE_KEY",
          "valueFrom" : "${var.secret_prefix}:rudder_stack_write_key::"
        },
        {
          "name" : "RECOMMENDATIONS_API_KEY",
          "valueFrom" : "${var.secret_prefix}:recommendations_api_key::"
        },
        {
          "name" : "BETTER_STACK_TOKEN",
          "valueFrom" : "${var.secret_prefix}:better_stack_token::"
        },
        {
          "name" : "API_KEY",
          "valueFrom" : "${var.secret_prefix}:API_KEY::"
        },
        {
          "name" : "MEDIA_PRIVATE_KEY_VALUE",
          "valueFrom" : var.media_private_key_arn
        },
        {
          "name" : "STRIPE_API_KEY",
          "valueFrom" : "${var.secret_prefix}:stripe_api_key::"
        },
        {
          "name" : "KNOCK_API_KEY",
          "valueFrom" : "${var.secret_prefix}:knock_api_key::"
        },
        {
          "name" : "SEARCH_API_KEY",
          "valueFrom" : "${var.secret_prefix}:SEARCH_API_KEY::"
        },
      ]
    }
  }

  subnet_ids               = var.private_subnets
  autoscaling_max_capacity = 2

  load_balancer = {
    service = {
      target_group_arn = var.alb_target_group_arn
      container_name   = "backend"
      container_port   = 8000
    }
  }

  service_connect_configuration = {
    enabled   = true
    namespace = var.service_connect_namespace
    service = [{
      port_name      = "backend"
      discovery_name = "backend-sc"
      client_alias = {
        dns_name = "backend"
        port     = 8000
      }
    }]
  }

  security_group_ingress_rules = {
    alb_ingress_8000 = {
      type                         = "ingress"
      from_port                    = 8000
      to_port                      = 8000
      protocol                     = "tcp"
      description                  = "Allow traffic from ALB"
      referenced_security_group_id = var.alb_security_group_id
    }

    monitoring_ingress_8000 = {
      type                         = "ingress"
      from_port                    = 8000
      to_port                      = 8000
      protocol                     = "tcp"
      description                  = "Allow traffic from monitoring service"
      referenced_security_group_id = var.monitoring_security_group_id
    }

    frontend_ingress_8000 = {
      type                         = "ingress"
      from_port                    = 8000
      to_port                      = 8000
      protocol                     = "tcp"
      description                  = "Allow traffic from frontend service"
      referenced_security_group_id = var.frontend_security_group_id
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
    exec_policy = var.task_exec_policy_arn
  }

  tasks_iam_role_statements = [
    {
      actions = [
        "events:PutEvents"
      ]
      effect    = "Allow"
      resources = [var.event_bus_arn]
    },
    {
      actions = [
        "s3:PutObject"
      ]
      effect = "Allow"
      resources = [
        var.media_bucket_arn,
        "${var.media_bucket_arn}/*"
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
        var.cognito_user_pool_arn
      ]
    },
    {
      actions = ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:GetItem", "dynamodb:Query"]
      effect  = "Allow"
      resources = [
        "arn:aws:dynamodb:eu-west-2:${data.aws_caller_identity.current.account_id}:table/production-ufb-recently-played"
      ]
    }
  ]

  tags = var.tags
}
