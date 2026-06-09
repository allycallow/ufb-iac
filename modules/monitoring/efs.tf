resource "aws_efs_file_system" "grafana" {
  encrypted = true
  tags      = merge(var.tags, { Name = "${var.name}-grafana" })
}

resource "aws_efs_file_system" "prometheus" {
  encrypted = true
  tags      = merge(var.tags, { Name = "${var.name}-prometheus" })
}

resource "aws_security_group" "efs" {
  name        = "${var.name}-efs"
  description = "Allow NFS from monitoring ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [module.monitoring_service.security_group_id]
  }

  tags = var.tags
}

resource "aws_efs_mount_target" "grafana" {
  for_each        = toset(var.private_subnets)
  file_system_id  = aws_efs_file_system.grafana.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "prometheus" {
  for_each        = toset(var.private_subnets)
  file_system_id  = aws_efs_file_system.prometheus.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "grafana" {
  file_system_id = aws_efs_file_system.grafana.id

  posix_user {
    uid = 472
    gid = 472
  }

  root_directory {
    path = "/grafana"
    creation_info {
      owner_uid   = 472
      owner_gid   = 472
      permissions = "755"
    }
  }

  tags = var.tags
}

resource "aws_efs_access_point" "prometheus" {
  file_system_id = aws_efs_file_system.prometheus.id

  posix_user {
    uid = 65534
    gid = 65534
  }

  root_directory {
    path = "/prometheus"
    creation_info {
      owner_uid   = 65534
      owner_gid   = 65534
      permissions = "755"
    }
  }

  tags = var.tags
}
