
module "rds_subnet_group" {
  source                = "./db_subnet_group"
  private_db_subnet_ids = var.private_db_subnet_ids
  project_name          = var.project_name
  SERVICE_CONFIG        = var.SERVICE_CONFIG
  environment           = var.environment
  vpc_id                = var.vpc_id
  db_sg_ids             = var.db_sg_ids
}


module "postgres_db" {
  source                  = "./postgres_db"
  private_db_subnet_ids   = var.private_db_subnet_ids
  project_name            = var.project_name
  SERVICE_CONFIG          = var.SERVICE_CONFIG
  rds_monitoring_role_arn = var.rds_monitoring_role_arn
  db_sg_ids               = var.db_sg_ids
  environment             = var.environment
  vpc_id                  = var.vpc_id
  db_sg_group_id          = module.rds_subnet_group.db_sg_group_id
  aries_db                = var.platform_db
  platform_db             = var.platform_db
  region                  = var.region
  public_subnet_ids       = var.public_subnet_ids
  rds_proxy_sg_ids        = var.rds_proxy_sg_ids
}
