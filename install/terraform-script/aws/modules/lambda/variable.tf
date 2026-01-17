variable "nats_efs_access_point_arn" {}
variable "private_app_subnet_ids" {
  type = list(string)
}

variable "nats_count" {}
variable "project_name" {}
variable "environment" {}
variable "SERVICE_CONFIG" {}
variable "nats_security_group_ids" {}
variable "profile" {}
variable "region" {}
