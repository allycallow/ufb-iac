module "security_group_open_search" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.name}-open-search"
  description = "Open Search security group"
  vpc_id      = var.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      description = "Access from within VPC"
      cidr_blocks = var.vpc_cidr_block
    },
  ]

  egress_with_cidr_blocks = [
    {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "All Traffic"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}

module "security_group_lambda_open_search" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.name}-lambda-open-search"
  description = "Lambda access to open Search security group"
  vpc_id      = var.vpc_id
}
