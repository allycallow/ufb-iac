resource "aws_db_parameter_group" "default" {
  name_prefix = "${local.name}-pg18-"
  family      = "postgres18"

  lifecycle {
    create_before_destroy = true
  }
}

module "db" {
  source = "terraform-aws-modules/rds/aws"

  identifier                          = local.name
  instance_use_identifier_prefix      = true
  create_db_option_group              = false
  create_db_parameter_group           = false
  engine                              = "postgres"
  engine_version                      = "18"
  family                              = "postgres18"
  major_engine_version                = "18"
  instance_class                      = "db.t4g.medium"
  allocated_storage                   = 20
  storage_type                        = "gp3"
  db_name                             = "ufb"
  username                            = "root"
  port                                = 5432
  iam_database_authentication_enabled = true
  db_subnet_group_name                = module.vpc.database_subnet_group
  vpc_security_group_ids              = [module.security_group_rds.security_group_id]
  deletion_protection                 = true
  storage_encrypted                   = true
  auto_minor_version_upgrade          = true
  allow_major_version_upgrade         = true
  max_allocated_storage               = 100
  skip_final_snapshot                 = false
  final_snapshot_identifier_prefix    = "${local.name}-final-snapshot"

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  maintenance_window      = "Mon:00:00-Mon:03:00"
  backup_window           = "03:00-06:00"
  backup_retention_period = 1
  parameter_group_name    = aws_db_parameter_group.default.name
  apply_immediately       = true
}

resource "aws_db_instance_role_association" "se_export" {
  db_instance_identifier = module.db.db_instance_identifier
  feature_name           = "s3Export"
  role_arn               = aws_iam_role.s3_rds.arn
}

output "db_instance_endpoint" {
  value = module.db.db_instance_endpoint
}
