# Log groups for services with defined ports
resource "aws_cloudwatch_log_group" "log_groups_with_port" {
  for_each = { for service in var.SERVICE_CONFIG.WITH_PORT : service.SERVICE_NAME => service }

  name = "/ecs/${var.project_name}_${var.environment}_${each.key}"
}

# Log groups for services without defined ports
resource "aws_cloudwatch_log_group" "log_groups_without_port" {
  for_each = toset(var.SERVICE_CONFIG.WITHOUT_PORT)

  name = "/ecs/${var.project_name}_${var.environment}_${each.value}"
}


resource "aws_cloudwatch_log_group" "log_groups_schema_file_server" {
  name = "/ecs/${var.project_name}_${var.environment}_${var.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME}"
}

resource "aws_cloudwatch_log_group" "log_groups_agent_provisioning_service" {
  name = "/ecs/${var.project_name}_${var.environment}_${var.AGENT_PROVISIONING_SERVICE.SERVICE_NAME}"
}

resource "aws_cloudwatch_log_group" "log_groups_nats_service" {
  count = lower(var.environment) != "prod" ? 1 : 3
  name  = "/ecs/${var.project_name}_${var.environment}_${var.SERVICE_CONFIG.NATS.SERVICE_NAME}_${count.index + 1}"

  # Use lifecycle to prevent recreation of an existing log group with the same name
  lifecycle {
    ignore_changes = [name]
  }
}

resource "aws_cloudwatch_log_group" "log_groups_redis_service" {
  name = "/ecs/${var.project_name}_${var.environment}_${var.REDIS_CONFIG.SERVICE_NAME}"
}