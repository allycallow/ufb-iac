resource "aws_iam_role" "s3_rds" {
  name = "${var.name}-RDSRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "rds.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_access_policy" {
  name = "s3-access"
  role = aws_iam_role.s3_rds.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:*",
          "s3-object-lambda:*"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy" "s3_export_policy" {
  name        = "AirflowS3ExportPolicy"
  description = "Allows Airflow to upload CSVs to the recommendations bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::ufb-db-exports/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::ufb-db-exports"
      }
    ]
  })
}

resource "aws_db_parameter_group" "default" {
  name_prefix = "${var.name}-pg18-"
  family      = "postgres18"

  lifecycle {
    create_before_destroy = true
  }
}

module "db" {
  source = "terraform-aws-modules/rds/aws"

  identifier                          = var.name
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
  db_subnet_group_name                = var.database_subnet_group
  vpc_security_group_ids              = [var.rds_sg_id]
  deletion_protection                 = true
  storage_encrypted                   = true
  auto_minor_version_upgrade          = true
  allow_major_version_upgrade         = true
  max_allocated_storage               = 100
  skip_final_snapshot                 = false
  final_snapshot_identifier_prefix    = "${var.name}-final-snapshot"

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

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.name}-app"
  engine               = "redis"
  node_type            = "cache.t4g.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.1"
  port                 = 6379
  security_group_ids   = [var.elasticache_sg_id]
  subnet_group_name    = var.elasticache_subnet_group
}
