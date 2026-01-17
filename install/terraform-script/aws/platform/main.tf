module "root" {
  source                   = "../modules/root"
  project_name             = var.project_name
  environment              = var.environment
  vpc_cidr                 = var.vpc_cidr
  public_subnet_cidr       = var.public_subnet_cidr
  private_app_subnet_cidr  = var.private_app_subnet_cidr
  private_db_subnet_cidr   = var.private_db_subnet_cidr
  profile                  = var.profile
  AWS_ACCOUNT_ID           = var.AWS_ACCOUNT_ID
  SENDGRID_API_KEY         = var.SENDGRID_API_KEY
  platform_db              = var.platform_db
  aries_db                 = var.aries_db
  region                   = var.region
  platform_seed            = var.platform_seed
  crypto_private_key       = var.crypto_private_key
  PLATFORM_WALLET_PASSWORD = var.PLATFORM_WALLET_PASSWORD
}

module "vpc" {
  source                  = "../modules/vpc"
  project_name            = module.root.project_name
  environment             = module.root.environment
  vpc_cidr                = module.root.vpc_cidr
  public_subnet_cidr      = module.root.public_subnet_cidr
  private_app_subnet_cidr = module.root.private_app_subnet_cidr
  private_db_subnet_cidr  = module.root.private_db_subnet_cidr
  depends_on              = [module.root]
}

module "nat_gateway" {
  source                     = "../modules/nat_gateway"
  project_name               = module.root.project_name
  environment                = module.root.environment
  vpc_id                     = module.vpc.vpc_id
  private_app_route_table_id = module.vpc.private_app_route_table_id
  private_db_route_table_id  = module.vpc.private_db_route_table_id
  public_subnet_ids          = module.vpc.public_subnet_ids
  depends_on                 = [module.vpc, module.root]
}

module "security_groups" {
  source                     = "../modules/security_group"
  environment                = module.root.environment
  project_name               = module.root.project_name
  vpc_id                     = module.vpc.vpc_id
  SCHEMA_FILE_SERVICE_CONFIG = module.root.SCHEMA_FILE_SERVICE_CONFIG
  SERVICE_CONFIG             = module.root.SERVICE_CONFIG
  AGENT_PROVISIONING_SERVICE = module.root.AGENT_PROVISIONING_SERVICE
  ALB_SG                     = module.root.ALB_SG
  depends_on                 = [module.nat_gateway, module.vpc, module.root]
}

module "ecr" {
  source         = "../modules/ecr"
  SERVICE_CONFIG = module.security_groups.SERVICE_CONFIG
  environment    = module.root.environment
  project_name   = module.root.project_name
  depends_on     = [module.security_groups]
}


module "iam" {
  source       = "../modules/iam"
  environment  = module.root.environment
  project_name = module.root.project_name


}
module "s3" {
  source             = "../modules/s3"
  environment        = module.root.environment
  project_name       = module.root.project_name
  ecs_tasks_role_arn = module.iam.ecs_tasks_execution_role_arn

}

module "efs" {
  source                 = "../modules/efs"
  environment            = module.root.environment
  project_name           = module.root.project_name
  vpc_id                 = module.vpc.vpc_id
  efs_sg_id              = module.security_groups.efs_sg_id
  private_app_subnet_ids = module.vpc.private_app_subnet_ids
  depends_on             = [module.security_groups]
}


module "db" {
  source                  = "../modules/db"
  environment             = module.root.environment
  project_name            = module.root.project_name
  vpc_id                  = module.vpc.vpc_id
  rds_monitoring_role_arn = module.iam.rds_monitoring_role_arn
  db_sg_ids               = module.security_groups.db_sg_ids
  private_db_subnet_ids   = module.vpc.private_db_subnet_ids
  SERVICE_CONFIG          = module.security_groups.SERVICE_CONFIG
  platform_db             = module.root.platform_db
  aries_db                = module.root.aries_db
  region                  = module.root.region
  public_subnet_ids       = module.vpc.public_subnet_ids
  rds_proxy_sg_ids        = module.security_groups.rds_proxy_sg_ids
  depends_on              = [module.security_groups]
}

module "alb" {
  source                        = "../modules/alb"
  project_name                  = module.root.environment
  environment                   = module.root.environment
  nats_alb_security_group_ids   = module.security_groups.nats_alb_security_group_ids
  SCHEMA_FILE_SERVICE_CONFIG    = module.security_groups.SCHEMA_FILE_SERVICE_CONFIG
  vpc_id                        = module.vpc.vpc_id
  public_subnet_ids             = module.vpc.public_subnet_ids
  nats_security_group_ids       = module.security_groups.nats_alb_security_group_ids
  alb_security_group_ids        = module.security_groups.alb_security_group_ids
  schema_file_service_alb_sg_id = module.security_groups.schema_file_service_alb_sg_id
  SERVICE_CONFIG                = module.security_groups.SERVICE_CONFIG
  app_security_group_ids        = module.security_groups.app_security_group_ids
}


module "lambda" {
  source                    = "../modules/lambda"
  environment               = module.root.environment
  project_name              = module.root.project_name
  nats_count                = module.security_groups.nats_count
  profile                   = var.profile
  region                    = var.region
  nats_efs_access_point_arn = module.efs.nats_efs_access_point_arn
  private_app_subnet_ids    = module.vpc.private_app_subnet_ids
  SERVICE_CONFIG            = module.security_groups.SERVICE_CONFIG
  nats_security_group_ids   = module.security_groups.nats_security_group_ids
  depends_on                = [module.efs, module.security_groups, module.vpc]
}


module "envfile" {
  source                     = "../modules/config_file"
  org_logo_bucket_id         = module.s3.org_logo_bucket_id
  env_file_bucket_arn        = module.s3.env_file_bucket_arn
  link_bucket_id             = module.s3.link_bucket_id
  env_file_bucket_id         = module.s3.env_file_bucket_id
  alb_dns_by_service         = module.alb.alb_dns_by_service
  SERVICE_CONFIG             = module.security_groups.SERVICE_CONFIG
  SCHEMA_FILE_SERVICE_CONFIG = module.security_groups.SCHEMA_FILE_SERVICE_CONFIG
  database_info_by_service   = module.db.database_info_by_service
  rds_proxy_info_by_service  = module.db.rds_proxy_info_by_service
  nats_count                 = module.security_groups.nats_count
  environment                = module.root.environment
  project_name               = module.root.project_name
  AGENT_PROVISIONING_SERVICE = module.security_groups.AGENT_PROVISIONING_SERVICE
  REDIS_CONFIG               = module.security_groups.REDIS_CONFIG
  region                     = var.region
  alb_details                = module.alb.alb_details
  org_logo_bucket_dns        = module.s3.org_logo_bucket_dns
  SENDGRID_API_KEY           = var.SENDGRID_API_KEY
  AWS_ACCOUNT_ID             = var.AWS_ACCOUNT_ID
  nats_seed_key              = module.lambda.nats_seed_key
  crypto_private_key         = module.root.crypto_private_key
  platform_seed              = module.root.platform_seed
  PLATFORM_WALLET_PASSWORD   = module.root.PLATFORM_WALLET_PASSWORD
  depends_on                 = [module.efs, module.s3, module.lambda]
}



module "cloudwatch_group" {
  source                     = "../modules/cloudwatch"
  environment                = module.root.environment
  project_name               = module.root.project_name
  SERVICE_CONFIG             = module.security_groups.SERVICE_CONFIG
  SCHEMA_FILE_SERVICE_CONFIG = module.security_groups.SCHEMA_FILE_SERVICE_CONFIG
  AGENT_PROVISIONING_SERVICE = module.security_groups.AGENT_PROVISIONING_SERVICE
  REDIS_CONFIG               = module.security_groups.REDIS_CONFIG
  depends_on                 = [module.security_groups]

}

module "ecs" {
  source                                = "../modules/ecs"
  environment                           = module.root.environment
  project_name                          = module.root.project_name
  vpc_id                                = module.vpc.vpc_id
  nats_security_group_ids               = module.security_groups.nats_security_group_ids
  public_subnet_ids                     = module.vpc.public_subnet_ids
  nats_efs_id                           = module.efs.nats_efs_id
  credo_efs_id                          = module.efs.credo_efs_id
  alb_security_group_ids                = module.security_groups.alb_security_group_ids
  schema_file_service_efs_id            = module.efs.schema_file_service_efs_id
  log_groups_with_port                  = module.cloudwatch_group.log_groups_with_port
  log_groups_without_port               = module.cloudwatch_group.log_groups_without_port
  log_groups_nats                       = module.cloudwatch_group.log_groups_nats
  SERVICE_CONFIG                        = module.security_groups.SERVICE_CONFIG
  app_security_group_ids                = module.security_groups.app_security_group_ids
  ecs_tasks_execution_role_arn          = module.iam.ecs_tasks_execution_role_arn
  ecs_tasks_role_arn                    = module.iam.ecs_tasks_role_arn
  env_file_bucket_arn                   = module.s3.env_file_bucket_arn
  region                                = var.region
  SCHEMA_FILE_SERVICE_CONFIG            = module.security_groups.SCHEMA_FILE_SERVICE_CONFIG
  AGENT_PROVISIONING_SERVICE            = module.security_groups.AGENT_PROVISIONING_SERVICE
  schema_file_service_sg_id             = module.security_groups.schema_file_service_sg_id
  log_groups_agent_provisioning_service = module.cloudwatch_group.log_groups_agent_provisioning_service
  log_groups_schema_file_server         = module.cloudwatch_group.log_groups_schema_file_server
  schema_file_service_alb_sg_id         = module.security_groups.schema_file_service_alb_sg_id
  nats_alb_security_group_ids           = module.security_groups.nats_alb_security_group_ids
  REDIS_CONFIG                          = module.security_groups.REDIS_CONFIG
  redis_efs_id                          = module.efs.redis_efs_id
  redis_sg_id                           = module.security_groups.redis_sg_id
  nats_target_group_arns                = module.alb.nats_target_group_arns
  target_group_arns                     = module.alb.target_group_arns
  schema_file_target_group_arn          = module.alb.schema_file_target_group_arn
  alb_details                           = module.alb.alb_details
  env_file_bucket_id                    = module.s3.env_file_bucket_id
  private_app_subnet_ids                = module.vpc.private_app_subnet_ids
  depends_on                            = [module.cloudwatch_group, module.db, module.iam, module.ecr, module.efs, module.envfile, module.lambda, module.envfile]
}
