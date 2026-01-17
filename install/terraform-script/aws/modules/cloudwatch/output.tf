# Outputs for CloudWatch log groups for services with defined ports
output "log_groups_with_port" {
  value = { for service_key, log_group in aws_cloudwatch_log_group.log_groups_with_port : service_key => log_group.name }
}

# Outputs for CloudWatch log groups for services without defined ports
output "log_groups_without_port" {
  description = "Log group names for services without defined ports"
  value = { for service_key, log_group in aws_cloudwatch_log_group.log_groups_without_port : service_key => log_group.name }
}

# Outputs for CloudWatch log groups for NATS services
output "log_groups_nats" {
  value = [for i in range(0, length(aws_cloudwatch_log_group.log_groups_nats_service)) : aws_cloudwatch_log_group.log_groups_nats_service[i].name]
}



output "log_groups_schema_file_server" {
  value = aws_cloudwatch_log_group.log_groups_schema_file_server.name
}

output "log_groups_agent_provisioning_service" {
 value = aws_cloudwatch_log_group.log_groups_agent_provisioning_service.name 
}

output "log_groups_redis_service" {
  value = aws_cloudwatch_log_group.log_groups_redis_service.name
}