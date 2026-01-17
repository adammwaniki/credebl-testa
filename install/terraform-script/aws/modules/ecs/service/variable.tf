
variable "target_group_arns" {}
variable "schema_file_target_group_arn" {}
variable "private_app_subnet_ids" {}
variable "app_security_group_ids" {}
variable "with_port_task_definitions" {
  description = "Map of ECS task definitions with their respective ARN keyed by service name"
  type = map(string)
}

variable "without_port_task_definitions" {
  description = "The ECS task definitions without ports"
  type = map(string)  # Map of task definition ARNs (strings)
}


variable "schema_file_server_task_definition" {}
variable "agent_provisioning_service_task_definition" {}
variable "nats_service_task_definitions" {}
variable "project_name" {}
variable "environment" {}
variable "SCHEMA_FILE_SERVICE_CONFIG" {
  
}
variable "AGENT_PROVISIONING_SERVICE" {}
variable "SERVICE_CONFIG" {
  
}
variable "schema_file_service_sg_id" {
  
}
variable "nats_target_group_arns" {
  
}
variable "nats_security_group_ids" {
  type = map(string)
}
 variable "nats_alb_security_group_ids" {
   
 }
 variable "redis_sg_id" {}
 variable "redis_server_task_definitions_arn" {}
 variable "REDIS_CONFIG" {}