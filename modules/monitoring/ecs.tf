module "monitoring_service" {
  source = "terraform-aws-modules/ecs/aws//modules/service"

  name        = var.name
  cluster_arn = var.ecs_cluster_arn

  cpu    = 1024 # 1 vCPU shared across both containers
  memory = 2048 # 2 GB RAM shared across both containers

  container_definitions = {
    prometheus = {
      cpu                    = 512
      memory                 = 1024
      image                  = "prom/prometheus:latest"
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
        EOF

        exec /bin/prometheus \
          --config.file=/etc/prometheus/prometheus.yml \
          --storage.tsdb.path=/prometheus \
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
      cpu                    = 512
      memory                 = 1024
      image                  = "grafana/grafana-oss:latest"
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
  }

  subnet_ids               = var.private_subnets
  autoscaling_max_capacity = 1
  desired_count            = 1

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
      description                  = "Allow traffic from ALB"
      referenced_security_group_id = var.alb_security_group_id
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

  tags = var.tags
}
