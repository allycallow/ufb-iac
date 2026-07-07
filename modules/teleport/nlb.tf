module "security_group_teleport_nlb" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.name}-teleport-nlb"
  description = "Teleport proxy NLB security group"
  vpc_id      = var.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Teleport proxy (web UI, tsh, db access)"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "All traffic"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  tags = var.tags
}

resource "aws_lb" "teleport" {
  name               = "${var.name}-teleport"
  load_balancer_type = "network"
  internal           = false
  subnets            = var.public_subnets
  security_groups    = [module.security_group_teleport_nlb.security_group_id]

  enable_deletion_protection       = true
  enable_cross_zone_load_balancing = true

  tags = var.tags
}

resource "aws_lb_target_group" "teleport" {
  name        = "${var.name}-teleport"
  port        = 3080
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "3080"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 15
  }

  tags = var.tags
}

resource "aws_lb_listener" "teleport" {
  load_balancer_arn = aws_lb.teleport.arn
  port              = 443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.teleport.arn
  }

  tags = var.tags
}
