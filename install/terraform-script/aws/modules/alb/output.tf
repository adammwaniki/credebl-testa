# Outputs for each ALB created
output "alb_arns" {
  description = "The ARNs of the ALBs created for each service"
  value = { for service, alb in aws_lb.alb : service => alb.arn }
}

# Outputs for each target group ARN
output "target_group_arns" {
  description = "The ARNs of the target groups created for each service"
  value = { for service, tg in aws_lb_target_group.app_tg : service => tg.arn }
}

# Outputs for the ALB DNS names (for each service)
output "alb_dns_names" {
  description = "The DNS names of the ALBs created for each service"
  value = { for service, alb in aws_lb.alb : service => alb.dns_name }
}
output "alb_details" {
  description = "The details of the ALBs created for each service, including ARNs and DNS names"
  value = {
    for service, alb in aws_lb.alb :
    service => {
      dns = alb.dns_name
    }
  }
}

output "alb_dns_by_service" {
  value = {
    for service, alb in aws_lb.alb : lower(service) => alb.dns_name
  }
  description = "ALB DNS names organized by service name"
}


# Output for the Schema File ALB ARN
output "schema_file_alb_arn" {
  description = "The ARN of the Schema File ALB"
  value = aws_lb.schema_file_alb.arn
}

# Output for the Schema File target group ARN
output "schema_file_target_group_arn" {
  description = "The ARN of the Schema File Target Group"
  value = aws_lb_target_group.schema_file_tg.arn
}

# Output for the Schema File ALB DNS name
output "schema_file_alb_dns" {
  description = "The DNS name of the Schema File ALB"
  value = aws_lb.schema_file_alb.dns_name
}


output "nats_target_group_arns" {
  value = [
    for tg in aws_lb_target_group.app_tg : tg.arn
  ]
  description = "The ARNs of the NATS target groups"
}


# Output for NLB ARN
output "nats_nlb_arn" {
  value       = aws_lb.nats_nlb.arn
  description = "The ARN of the NATS NLB"
}

# Output for NLB DNS name
output "nats_nlb_dns_name" {
  value       = aws_lb.nats_nlb.dns_name
  description = "The DNS name of the NATS NLB"
}