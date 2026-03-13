resource "aws_db_parameter_group" "default" {
  name   = "${local.name}-pg-group"
  family = "postgres15"
}

module "db" {
  source = "terraform-aws-modules/rds/aws"

  identifier                          = local.name
  instance_use_identifier_prefix      = true
  create_db_option_group              = false
  create_db_parameter_group           = false
  engine                              = "postgres"
  engine_version                      = "15"
  family                              = "postgres15"
  major_engine_version                = "15"
  instance_class                      = "db.t4g.micro"
  allocated_storage                   = 20
  storage_type                        = "gp3"
  db_name                             = "ufb"
  username                            = "root"
  port                                = 5432
  iam_database_authentication_enabled = true
  db_subnet_group_name                = module.vpc.database_subnet_group
  vpc_security_group_ids              = [module.security_group_rds.security_group_id]
  deletion_protection                 = true

  maintenance_window      = "Mon:00:00-Mon:03:00"
  backup_window           = "03:00-06:00"
  backup_retention_period = 0 # ⚠️ No backups – safe for dev only
  parameter_group_name    = aws_db_parameter_group.default.name
}

resource "aws_db_instance_role_association" "se_export" {
  db_instance_identifier = module.db.db_instance_identifier
  feature_name           = "s3Export"
  role_arn               = aws_iam_role.s3_rds.arn
}

output "db_instance_endpoint" {
  value = module.db.db_instance_endpoint
}
