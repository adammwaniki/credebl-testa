data "aws_rds_engine_version" "latest_postgres" {
  engine = "postgres"
}


resource "random_string" "db_passwords" {
  for_each = local.db_configs
  length   = 16
  upper    = true
  numeric  = true
  special  = false
}

resource "aws_db_instance" "rds_instance" {
  for_each               = local.db_configs
  identifier             = "${lower(replace("${var.project_name}-${var.environment}-${each.key}", "_", "-"))}-db"
  instance_class         = each.key == "MEDIATOR" || each.key == "CREDO" ? var.aries_db : var.platform_db
  engine                 = "postgres"
  engine_version         = data.aws_rds_engine_version.latest_postgres.version
  allocated_storage      = var.environment == "dev" ? 30 : (each.key == "MEDIATOR" || each.key == "CREDO" ? 100 : 50)
  storage_type           = var.environment == "dev" ? "gp2" : (each.key == "MEDIATOR" || each.key == "CREDO" ? "io2" : "gp2")
  max_allocated_storage = 500
  # Set IOPS conditionally based on storage type
  iops                   = var.environment == "dev" ? "gp2" : (each.key == "MEDIATOR" || each.key == "CREDO" ? each.value.iops : null)

  multi_az               = true
  username               = each.value.username
  password               = random_string.db_passwords[(each.key)].result
  db_name                = each.value.db_name
  db_subnet_group_name   = var.db_sg_group_id
  vpc_security_group_ids = [each.value.db_sg_id]

  # Monitoring role and interval
  monitoring_role_arn                   = var.rds_monitoring_role_arn
  monitoring_interval                    = 1  # Set to a value greater than 0
  backup_retention_period                = 15
  enabled_cloudwatch_logs_exports        = ["postgresql", "upgrade"]
  performance_insights_enabled           = true
  performance_insights_retention_period  = 31
  skip_final_snapshot                   = true

  tags = {
    Name        = "${var.project_name}-${each.key}-rds"
    Environment = var.environment
  }
}

