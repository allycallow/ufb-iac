resource "aws_efs_file_system" "teleport_data" {
  creation_token = "${var.name}-teleport-data"
  encrypted      = true

  tags = merge(var.tags, {
    Name = "${var.name}-teleport-data"
  })
}

resource "aws_efs_access_point" "teleport_data" {
  file_system_id = aws_efs_file_system.teleport_data.id

  posix_user {
    uid = 0
    gid = 0
  }

  root_directory {
    path = "/teleport-data"
    creation_info {
      owner_uid   = 0
      owner_gid   = 0
      permissions = "0700"
    }
  }

  tags = var.tags
}

module "security_group_teleport_efs" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.name}-teleport-efs"
  description = "Teleport EFS mount target security group"
  vpc_id      = var.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = 2049
      to_port                  = 2049
      protocol                 = "tcp"
      description              = "NFS from Teleport ECS task"
      source_security_group_id = module.teleport_task_definition.security_group_id
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

resource "aws_efs_mount_target" "teleport_data" {
  for_each = toset(var.private_subnets)

  file_system_id  = aws_efs_file_system.teleport_data.id
  subnet_id       = each.value
  security_groups = [module.security_group_teleport_efs.security_group_id]
}
