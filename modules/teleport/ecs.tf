locals {
  teleport_config = <<-EOF
    version: v3
    teleport:
      nodename: ${var.name}-teleport
      data_dir: /var/lib/teleport
      log:
        severity: DEBUG
      storage:
        type: dynamodb
        region: ${var.region}
        table_name: ${aws_dynamodb_table.teleport_state.name}
        audit_events_uri: ["dynamodb://${aws_dynamodb_table.teleport_events.name}"]
        audit_sessions_uri: "s3://${aws_s3_bucket.teleport_sessions.bucket}"

    auth_service:
      enabled: true
      proxy_listener_mode: multiplex
      authentication:
        type: local
        second_factor: "on"
        webauthn:
          rp_id: ${var.public_addr}

    proxy_service:
      enabled: true
      web_listen_addr: 0.0.0.0:3080
      public_addr: ${var.public_addr}:443
      tunnel_listen_addr: 0.0.0.0:3024
      acme:
        enabled: true
        email: ${var.acme_email}

    db_service:
      enabled: true
      databases:
      - name: rds-postgres
        protocol: postgres
        uri: "${var.db_instance_endpoint}"
        aws:
          region: ${var.region}
          rds:
            instance_id: ${var.db_instance_identifier}
      - name: elasticache-redis
        protocol: redis
        uri: "${var.redis_endpoint}"
        aws:
          region: ${var.region}
          elasticache:
            replication_group_id: ${var.redis_replication_group_id}
      - name: opensearch
        protocol: opensearch
        uri: "${var.opensearch_domain_endpoint}:443"
        aws:
          region: ${var.region}
          account_id: ${var.account_id}

    ssh_service:
      enabled: false
    app_service:
      enabled: true
      apps:
      - name: search
        uri: http://search:8000
      - name: recommendations
        uri: http://recommendations:8000
  EOF
}

module "teleport_task_definition" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name                 = "${var.name}-teleport"
  cluster_arn          = var.ecs_cluster_arn
  force_new_deployment = true

  runtime_platform = {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  cpu    = 256
  memory = 1024

  enable_execute_command = true

  volume = {
    "teleport-config" = {}
  }

  container_definitions = {
    config-writer = {
      cpu                    = 0
      memory                 = 128
      essential              = false
      image                  = "public.ecr.aws/docker/library/busybox:1.36.1"
      user                   = "0"
      readonlyRootFilesystem = false
      entrypoint             = ["/bin/sh", "-ec"]
      command = [<<-EOT
        cat <<'EOF' >/etc/teleport/teleport.yaml
        ${local.teleport_config}
        EOF
      EOT
      ]

      mountPoints = [
        {
          sourceVolume  = "teleport-config"
          containerPath = "/etc/teleport"
          readOnly      = false
        }
      ]

      enable_cloudwatch_logging = true
    }

    teleport = {
      cpu                    = 256
      memory                 = 896
      essential              = true
      image                  = "public.ecr.aws/gravitational/teleport-distroless:18.7.3"
      user                   = "0"
      readonlyRootFilesystem = false

      dependsOn = [
        {
          containerName = "config-writer"
          condition     = "SUCCESS"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "teleport-config"
          containerPath = "/etc/teleport"
          readOnly      = true
        }
      ]

      portMappings = [
        {
          name          = "teleport-proxy"
          containerPort = 3080
          hostPort      = 3080
          protocol      = "tcp"
        }
      ]

      enable_cloudwatch_logging = true
    }
  }

  subnet_ids               = var.private_subnets
  autoscaling_max_capacity = 1
  desired_count            = 1

  service_connect_configuration = {
    enabled   = true
    namespace = var.service_connect_namespace
  }

  load_balancer = {
    service = {
      target_group_arn = aws_lb_target_group.teleport.arn
      container_name   = "teleport"
      container_port   = 3080
    }
  }

  security_group_ingress_rules = {
    nlb_ingress_3080 = {
      type                         = "ingress"
      from_port                    = 3080
      to_port                      = 3080
      protocol                     = "tcp"
      description                  = "Allow traffic from Teleport NLB"
      referenced_security_group_id = module.security_group_teleport_nlb.security_group_id
    }
  }

  security_group_egress_rules = {
    all = {
      type        = "egress"
      from_port   = 0
      to_port     = 65535
      protocol    = "-1"
      description = "Allow traffic anywhere (RDS/Redis/OpenSearch access + ACME/Lets Encrypt)"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  create_task_exec_iam_role = true
  task_exec_iam_role_name   = "${var.name}-teleport-exec"
  task_exec_iam_role_policies = {
    exec_policy = var.task_exec_policy_arn
  }

  tasks_iam_role_statements = [
    {
      sid    = "RdsIamConnect"
      effect = "Allow"
      actions = [
        "rds-db:connect"
      ]
      resources = [
        "arn:aws:rds-db:${var.region}:${var.account_id}:dbuser:${var.db_instance_resource_id}/${var.teleport_db_username}"
      ]
    },
    {
      sid    = "RdsDescribe"
      effect = "Allow"
      actions = [
        "rds:DescribeDBInstances"
      ]
      resources = ["*"]
    },
    {
      sid    = "AssumeOpenSearchRole"
      effect = "Allow"
      actions = [
        "sts:AssumeRole"
      ]
      resources = [aws_iam_role.opensearch_access.arn]
    },
    {
      sid    = "TeleportStateBackend"
      effect = "Allow"
      actions = [
        "dynamodb:BatchGetItem",
        "dynamodb:BatchWriteItem",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:DescribeTable",
        "dynamodb:UpdateTable",
        "dynamodb:DescribeTimeToLive",
        "dynamodb:UpdateTimeToLive",
        "dynamodb:ListStreams",
        "dynamodb:DescribeStream",
        "dynamodb:GetRecords",
        "dynamodb:GetShardIterator"
      ]
      resources = [
        aws_dynamodb_table.teleport_state.arn,
        "${aws_dynamodb_table.teleport_state.arn}/index/*",
        "${aws_dynamodb_table.teleport_state.arn}/stream/*",
        aws_dynamodb_table.teleport_events.arn,
        "${aws_dynamodb_table.teleport_events.arn}/index/*"
      ]
    },
    {
      sid    = "TeleportSessionsBucket"
      effect = "Allow"
      actions = [
        "s3:GetBucketLocation",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:GetObject",
        "s3:PutObject",
        "s3:GetObjectVersion",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload"
      ]
      resources = [
        aws_s3_bucket.teleport_sessions.arn,
        "${aws_s3_bucket.teleport_sessions.arn}/*"
      ]
    }
  ]

  tags = var.tags
}
