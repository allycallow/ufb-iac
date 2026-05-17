module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name               = local.name
  load_balancer_type = "application"
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = true

  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }

    all_https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      description = "HTTPS web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }

  target_groups = {
    frontend = {
      backend_protocol                  = "HTTP"
      backend_port                      = 3000
      target_type                       = "ip"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true

      health_check = {
        enabled             = true
        healthy_threshold   = 3
        interval            = 15
        matcher             = "200-399"
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }

      create_attachment = false
    }

    backend = {
      backend_protocol                  = "HTTP"
      backend_port                      = 8000
      target_type                       = "ip"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true

      health_check = {
        enabled             = true
        healthy_threshold   = 3
        interval            = 15
        matcher             = "200-399"
        path                = "/ping/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }

      create_attachment = false
    }

    airflow = {
      backend_protocol                  = "HTTP"
      backend_port                      = 8080
      target_type                       = "ip"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true

      health_check = {
        enabled             = true
        healthy_threshold   = 3
        interval            = 15
        matcher             = "200-399"
        path                = "/api/v2/monitor/health"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }

      create_attachment = false
    }

    search = {
      backend_protocol                  = "HTTP"
      backend_port                      = 8080
      target_type                       = "ip"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true

      health_check = {
        enabled             = true
        healthy_threshold   = 3
        interval            = 15
        matcher             = "200-399"
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }

      create_attachment = false
    }

    recommendations = {
      backend_protocol                  = "HTTP"
      backend_port                      = 8080
      target_type                       = "ip"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true

      health_check = {
        enabled             = true
        healthy_threshold   = 3
        interval            = 15
        matcher             = "200-399"
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }

      create_attachment = false
    }

    monitoring = {
      backend_protocol                  = "HTTP"
      backend_port                      = 3000
      target_type                       = "ip"
      deregistration_delay              = 5
      load_balancing_cross_zone_enabled = true

      health_check = {
        enabled             = true
        healthy_threshold   = 3
        interval            = 15
        matcher             = "200-399"
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }

      create_attachment = false
    }
  }

  listeners = {
    http-https-redirect = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = "arn:aws:acm:eu-west-2:081077757258:certificate/b9dfadd8-f77e-4591-ba0a-e2f4c31a7c48"

      forward = {
        target_group_key = "frontend"
      }

      rules = {
        frontend = {
          priority = 1
          conditions = [{
            host_header = {
              values = ["production.upfrontbeats.com"]
            }
          }]
          actions = [{
            type             = "forward"
            target_group_key = "frontend"
          }]
        }

        backend = {
          priority = 2
          conditions = [{
            host_header = {
              values = ["new-admin.upfrontbeats.com"]
            }
          }]
          actions = [{
            type             = "forward"
            target_group_key = "backend"
          }]
        }

        airflow = {
          priority = 3
          conditions = [{
            host_header = {
              values = ["airflow.upfrontbeats.com"]
            }
          }]
          actions = [{
            type             = "forward"
            target_group_key = "airflow"
          }]
        }

        search = {
          priority = 4
          conditions = [{
            host_header = {
              values = ["search.upfrontbeats.com"]
            }
          }]
          actions = [{
            type             = "forward"
            target_group_key = "search"
          }]
        }

        recommendations = {
          priority = 5
          conditions = [{
            host_header = {
              values = ["recommendations.upfrontbeats.com"]
            }
          }]
          actions = [{
            type             = "forward"
            target_group_key = "recommendations"
          }]
        }

        monitoring = {
          priority = 6
          conditions = [{
            host_header = {
              values = ["monitoring.upfrontbeats.com"]
            }
          }]
          actions = [{
            type             = "forward"
            target_group_key = "monitoring"
          }]
        }
      }
    }
  }
}
