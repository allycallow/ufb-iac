module "monitoring_service" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name        = var.name
  cluster_arn = var.ecs_cluster_arn

  cpu    = 512
  memory = 3072

  container_definitions = {
    prometheus = {
      memory                 = 1024
      image                  = "prom/prometheus:v2.55.1"
      essential              = true
      readonlyRootFilesystem = false
      entrypoint             = ["/bin/sh", "-ec"]
      command = [<<-EOT
        cat <<'EOF' >/etc/prometheus/prometheus.yml
        global:
          scrape_interval: 15s

        scrape_configs:
          - job_name: prometheus
            static_configs:
              - targets: ['localhost:9090']

          - job_name: backend
            metrics_path: /metrics
            scheme: https
            static_configs:
              - targets: ['new-admin.upfrontbeats.com']

          - job_name: recommendations
            metrics_path: /metrics
            scheme: https
            static_configs:
              - targets: ['recommendations.upfrontbeats.com']

          - job_name: search
            metrics_path: /metrics
            scheme: https
            static_configs:
              - targets: ['search.upfrontbeats.com']
        EOF

        exec /bin/prometheus \
          --config.file=/etc/prometheus/prometheus.yml \
          --storage.tsdb.path=/prometheus \
          --enable-feature=exemplar-storage \
          --web.console.libraries=/usr/share/prometheus/console_libraries \
          --web.console.templates=/usr/share/prometheus/consoles
      EOT
      ]
      portMappings = [
        {
          name          = "prometheus"
          containerPort = 9090
          hostPort      = 9090
          protocol      = "tcp"
        }
      ]
      enable_cloudwatch_logging = true
    }

    grafana = {
      memory                 = 1024
      image                  = "grafana/grafana-oss:11.4.0"
      essential              = true
      readonlyRootFilesystem = false
      portMappings = [
        {
          name          = "grafana"
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]
      enable_cloudwatch_logging = true
    }

    # NEW: Grafana Tempo Container Added to the Sidecar Stack
    tempo = {
      memory                 = 1024
      image                  = "grafana/tempo:2.6.1"
      essential              = true
      readonlyRootFilesystem = false
      entrypoint             = ["/bin/sh", "-ec"]
      command = [<<-EOT
        cat <<'EOF' >/tmp/tempo.yaml
        server:
          http_listen_port: 3200

        distributor:
          receivers:
            otlp:
              protocols:
                grpc:
                  endpoint: 0.0.0.0:4317
                http:
                  endpoint: 0.0.0.0:4318

        storage:
          trace:
            backend: s3
            wal:
              path: /tmp/tempo/wal
            s3:
              bucket: ${var.name}-tempo-traces
              region: eu-west-2
              endpoint: s3.eu-west-2.amazonaws.com

        compactor:
          compaction:
            compacted_block_retention: 48h
        EOF

        exec /tempo -config.file=/tmp/tempo.yaml
      EOT
      ]
      portMappings = [
        {
          name          = "tempo-otlp-grpc"
          containerPort = 4317
          hostPort      = 4317
          protocol      = "tcp"
        },
        {
          name          = "tempo-http"
          containerPort = 3200
          hostPort      = 3200
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
    service = [{
      port_name      = "tempo-otlp-grpc"
      discovery_name = "tempo-sc"
      client_alias = {
        dns_name = "tempo"
        port     = 4317
      }
    }]
  }

  load_balancer = {
    service = {
      target_group_arn = var.alb_target_group_arn
      container_name   = "grafana"
      container_port   = 3000
    }
  }

  security_group_ingress_rules = {
    alb_ingress_3000 = {
      type                         = "ingress"
      from_port                    = 3000
      to_port                      = 3000
      protocol                     = "tcp"
      description                  = "Allow traffic from ALB to Grafana"
      referenced_security_group_id = var.alb_security_group_id
    }

    # NEW INGRESS RULE: Allows your Django and FastAPI applications to push traces to Tempo
    app_ingress_4317 = {
      type        = "ingress"
      from_port   = 4317
      to_port     = 4317
      protocol    = "tcp"
      description = "Allow OTLP tracing traffic from applications to Tempo"
      cidr_ipv4   = var.vpc_cidr_block
    }
  }

  security_group_egress_rules = {
    all = {
      type        = "egress"
      from_port   = 0
      to_port     = 65535
      protocol    = "-1"
      description = "Allow traffic to anywhere (Crucial for Tempo to reach S3)"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  # NEW: Attaches your S3 IAM policy directly to the combined monitoring task role
  tasks_iam_role_policies = {
    TempoS3Access = aws_iam_policy.tempo_s3_access.arn
  }

  tags = var.tags
}
