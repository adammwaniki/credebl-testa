
module "taskdenitions" {
  source = "./taskdefinition"
  ecs_tasks_execution_role_arn = var.ecs_tasks_execution_role_arn
  ecs_tasks_role_arn = var.ecs_tasks_role_arn
  env_file_bucket_arn = var.env_file_bucket_arn
  credo_efs_id = var.credo_efs_id
  schema_file_service_efs_id = var.schema_file_service_efs_id
  nats_efs_id = var.nats_efs_id
  environment = var.environment
  project_name = var .project_name
  log_groups_nats = var.log_groups_nats
  log_groups_with_port = var.log_groups_with_port
  log_groups_without_port = var.log_groups_without_port
  app_security_group_ids = var.app_security_group_ids
  vpc_id = var.vpc_id
  nats_security_group_ids = var.nats_security_group_ids
  public_subnet_ids = var.public_subnet_ids
  region = var.region
  alb_security_group_ids = var.alb_security_group_ids
  SERVICE_CONFIG = var.SERVICE_CONFIG
  AGENT_PROVISIONING_SERVICE = var.AGENT_PROVISIONING_SERVICE
  SCHEMA_FILE_SERVICE_CONFIG = var.SCHEMA_FILE_SERVICE_CONFIG
  log_groups_agent_provisioning_service = var.log_groups_agent_provisioning_service
  schema_file_service_sg_id = var.schema_file_service_efs_id
  log_groups_schema_file_server = var.log_groups_schema_file_server
  redis_efs_id = var.redis_efs_id
  REDIS_CONFIG = var.REDIS_CONFIG
}

module "service" {
  source = "./service"
  private_app_subnet_ids = var.private_app_subnet_ids
  environment = var.environment
  project_name = var.project_name
  nats_service_task_definitions = module.taskdenitions.nats_service_task_definitions
  schema_file_server_task_definition = module.taskdenitions.schema_file_server_task_definition
  with_port_task_definitions = module.taskdenitions.with_port_task_definitions
  without_port_task_definitions = module.taskdenitions.without_port_task_definitions
  target_group_arns = var.target_group_arns
  agent_provisioning_service_task_definition = module.taskdenitions.agent_provisioning_service_task_definition
  schema_file_target_group_arn = var.schema_file_target_group_arn
  app_security_group_ids = var.app_security_group_ids
  AGENT_PROVISIONING_SERVICE =var.AGENT_PROVISIONING_SERVICE
  SCHEMA_FILE_SERVICE_CONFIG = var.SCHEMA_FILE_SERVICE_CONFIG
  SERVICE_CONFIG=var.SERVICE_CONFIG
  schema_file_service_sg_id = var.schema_file_service_sg_id
  nats_target_group_arns = var.nats_target_group_arns
  nats_alb_security_group_ids = var.nats_alb_security_group_ids
  nats_security_group_ids = var.nats_security_group_ids
  redis_sg_id = var.redis_sg_id
  redis_server_task_definitions_arn=module.taskdenitions.redis_server_task_definitions_arn
  REDIS_CONFIG = var.REDIS_CONFIG
}

# module "keycloak" {
#   source = "./KEYCLOAK"
#   environment = var.environment
#   env_file_bucket_id = var.env_file_bucket_id
#   alb_details = var.alb_details
# }