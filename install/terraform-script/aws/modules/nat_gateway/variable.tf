variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "project_name" {}
variable "environment" {}


variable "vpc_id" {}

variable "nat_gateway_count" {
  description = "Number of NAT Gateways to create"
  type        = number
  default     = 2
}

variable "private_db_route_table_id" {
  
}
variable "private_app_route_table_id" {
  
}