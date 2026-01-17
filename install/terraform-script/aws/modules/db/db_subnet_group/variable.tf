variable "db_sg_ids" {
  type        = map(string)
  description = "Map of database security group IDs for each service requiring a DB port"
}
variable "private_db_subnet_ids" {
  type = list(string)
}
variable "project_name" {
  
}
variable "environment" {
  
}
variable "vpc_id" {
  
}

variable "SERVICE_CONFIG" {}