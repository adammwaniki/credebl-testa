output "alb_security_group_ids" {
  description = "Security Group IDs for each service ALB"
  value       = { for key, sg in aws_security_group.ALB_SG : key => sg.id }
}

output "app_security_group_ids" {
  description = "Security Group IDs for each application"
  value       = { for key, sg in aws_security_group.APP_SG : key => sg.id }
}

# Output for Database security group IDs (only for services with a DB_PORT)
output "db_sg_ids" {
  value       = { for name, sg in aws_security_group.DB_SG : name => sg.id }
  description = "Database Security Group IDs for each service with a DB port"
}

# Output for Database proxy security group IDs (only for services with a DB_PORT)
output "rds_proxy_sg_ids" {
  value       = { for name, sg in aws_security_group.RDS_PROXY_SG : name => sg.id }
  description = "Database Security Group IDs for each service with a DB port"
}

output "nats_count" {
  value = length(aws_security_group.NATS_SG)
}

output "nats_security_group_ids" {
  description = "Security Group IDs for NATS services"
  value       = { for idx, sg in aws_security_group.NATS_SG : sg.name => sg.id }
  sensitive   = true
}

output "nats_alb_security_group_ids" {
  value     = { for idx, sg in aws_security_group.NATS_ALB_SG : sg.name => sg.id }
  sensitive = true
}

output "SERVICE_CONFIG" {
  description = "service data"
  value       = var.SERVICE_CONFIG
}


output "efs_sg_id" {
  value = aws_security_group.EFS_SG.id
}

output "schema_file_service_sg_id" {
  value = aws_security_group.SCHEMA_FILE_SERVICE_SG.id
}

output "AGENT_PROVISIONING_SERVICE" {
  value = var.AGENT_PROVISIONING_SERVICE
}

output "SCHEMA_FILE_SERVICE_CONFIG" {
  value = var.SCHEMA_FILE_SERVICE_CONFIG
}

output "schema_file_service_alb_sg_id" {
  value = aws_security_group.SCHEMA_FILE_SERVICE_ALB_SG.id
}

output "redis_sg_id" {
  value = aws_security_group.REDIS_SG.id
}

output "REDIS_CONFIG" {
  value = local.REDIS_CONFIG
}


