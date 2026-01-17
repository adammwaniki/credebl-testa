variable "db_sg_ids" {
  type        = map(string)
  description = "Map of database security group IDs for each service requiring a DB port"
}
variable "private_db_subnet_ids" {}
variable "project_name" {}
variable "environment" {}
variable "vpc_id" {}
variable "SERVICE_CONFIG" {}
variable "rds_monitoring_role_arn" {}
variable "db_sg_group_id" {}
variable "aries_db" {}
variable "platform_db" {}
variable "region" {}
variable "public_subnet_ids" {}
variable "rds_proxy_sg_ids" {}