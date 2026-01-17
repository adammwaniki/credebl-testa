variable "environment" {}
variable "project_name" {}
variable "vpc_id" {}
variable "alb_security_group_ids" {}
variable "SERVICE_CONFIG" {}
variable "app_security_group_ids" {
  type = map(string)
}
variable "nats_security_group_ids" {
 type = map(string)
}

variable "public_subnet_ids" {}
variable "private_app_subnet_ids" {}
variable "env_file_bucket_arn" {}
variable "ecs_tasks_execution_role_arn" {}
variable "ecs_tasks_role_arn" {}
variable "log_groups_nats" {}
variable "log_groups_without_port" {}
variable "log_groups_with_port" {}
variable "region" {}
variable "schema_file_service_efs_id" {}
variable "credo_efs_id" {}
variable "nats_efs_id" {}
variable "schema_file_service_sg_id" {}
variable "SCHEMA_FILE_SERVICE_CONFIG" {}
variable "log_groups_schema_file_server" {}
variable "AGENT_PROVISIONING_SERVICE" {}
variable "log_groups_agent_provisioning_service" {}
variable "schema_file_service_alb_sg_id" {}
 variable "nats_alb_security_group_ids" {}
 variable "redis_efs_id" {}
 variable "redis_sg_id" {}
 variable "REDIS_CONFIG" {}
 variable "target_group_arns" {}
 variable "nats_target_group_arns" {}
 variable "schema_file_target_group_arn" {}


 #keycloak
 variable "env_file_bucket_id" {}
 variable "alb_details" {}