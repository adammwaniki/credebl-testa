resource "aws_ecs_cluster" "cluster" {
  name = upper("${var.environment}-${var.project_name}_cluster")
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_service" "withport_server" {
  for_each           = { for service in var.SERVICE_CONFIG.WITH_PORT : service.SERVICE_NAME => service}

  name               = "${each.value.SERVICE_NAME}_SERVICE"
  cluster            = aws_ecs_cluster.cluster.id
  task_definition    = var.with_port_task_definitions[each.value.SERVICE_NAME]
  launch_type        = "FARGATE"
   desired_count = each.value["SERVICE_NAME"] == "KEYCLOAK" ? 1 : local.ecs_service_desired_count

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [lookup(var.app_security_group_ids, each.value.SERVICE_NAME, "default_sg_id")]
    assign_public_ip = false  # Update based on your requirements
  }

  load_balancer {
    target_group_arn = var.target_group_arns[each.value.SERVICE_NAME]
    container_name   = each.value.SERVICE_NAME
    container_port   = each.value.PORT
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.cluster_namespace.arn

    service {
      port_name      = lower("${each.value.SERVICE_NAME}-${each.value.PORT}-tcp")
      discovery_name = lower("${each.value.SERVICE_NAME}-sc")
      client_alias {
        port = each.value.PORT
      }
    }
  }

  depends_on = [var.target_group_arns]
}


# Schema File Server Service (second service definition)
resource "aws_ecs_service" "schema_file_server" {
  name            = upper("${var.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME}_SERVICE")
  cluster         = aws_ecs_cluster.cluster.name
  task_definition = var.schema_file_server_task_definition
  desired_count   = local.ecs_service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.schema_file_service_sg_id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = var.schema_file_target_group_arn
    container_name   = var.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME
    container_port   = var.SCHEMA_FILE_SERVICE_CONFIG.PORT
  }

   service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.cluster_namespace.arn
    service {
      port_name      = lower("${var.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME}-${var.SCHEMA_FILE_SERVICE_CONFIG.PORT}-tcp")
      discovery_name = lower("${var.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME}-sc")
      client_alias {
        port = var.SCHEMA_FILE_SERVICE_CONFIG.PORT
      }
    }
  }

  depends_on = [var.schema_file_target_group_arn]
}

# Agent Provisioning Service
resource "aws_ecs_service" "agent_provisioning_service" {
  name            = upper("${var.AGENT_PROVISIONING_SERVICE.SERVICE_NAME}_SERVICE")
  cluster         = aws_ecs_cluster.cluster.name
  task_definition = var.agent_provisioning_service_task_definition
  desired_count   = local.ecs_service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [lookup(var.app_security_group_ids, "API_GATEWAY", "default_sg_id")]
    assign_public_ip = true
  }

   service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.cluster_namespace.arn
   
  }

  depends_on = [aws_ecs_cluster.cluster]
}


# Without Port Service
resource "aws_ecs_service" "withoutport_service" {
  for_each = var.without_port_task_definitions

  name               = "${each.key}_SERVICE"  # The service name
  cluster            = aws_ecs_cluster.cluster.id
  task_definition    = each.value  # Directly reference the ARN string
  launch_type        = "FARGATE"
  desired_count      = local.ecs_service_desired_count

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [lookup(var.app_security_group_ids, "API_GATEWAY", "default_sg_id")]
    assign_public_ip = true
  }
  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.cluster_namespace.arn
  }
  depends_on = [
    aws_ecs_cluster.cluster,aws_ecs_service.agent_provisioning_service
  ]
}




# Define NATS ECS Serviceresource "aws_ecs_service" "nats_service" {
resource "aws_ecs_service" "nats_service" {
  count = lower(var.environment) != "prod" ? 1 : 3  # Create only 1 for dev, 3 for prod

  name            = "NATS-${count.index + 1}_SERVICE"
  cluster         = aws_ecs_cluster.cluster.id  # ECS Cluster ID
  task_definition = var.nats_service_task_definitions[count.index]  # Task definition ARN from the task definition module
  desired_count   = 1  # The number of tasks you want running
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [values(var.nats_security_group_ids)[count.index]]  # Convert the map to a list and use index
    assign_public_ip = true  # Whether to assign a public IP to the tasks
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.cluster_namespace.arn

    dynamic "service" {
      for_each = toset(var.SERVICE_CONFIG.NATS.PORT)  # Iterate over the ports list
      content {
        port_name      = lower("${var.SERVICE_CONFIG.NATS.SERVICE_NAME}-${count.index+1}-${service.value}-tcp")
        discovery_name = lower("${var.SERVICE_CONFIG.NATS.SERVICE_NAME}-${count.index+1}-${service.value}")
        client_alias {
          port = service.value
          
        }
      }
    }
  }

  depends_on = [
    var.nats_service_task_definitions  # Ensure task definitions are created first
  ]
}



# RedisServer Service (second service definition)
resource "aws_ecs_service" "redis_server" {
  name            = upper("${var.REDIS_CONFIG.SERVICE_NAME}_SERVICE")
  cluster         = aws_ecs_cluster.cluster.name
  task_definition = var.redis_server_task_definitions_arn
  desired_count   = local.ecs_service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_app_subnet_ids
    security_groups  = [var.redis_sg_id]
    assign_public_ip = true
  }
   service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.cluster_namespace.arn
    service {
      port_name      = lower("${var.REDIS_CONFIG.SERVICE_NAME}-${var.REDIS_CONFIG.PORT}-tcp")
      discovery_name = lower("${var.REDIS_CONFIG.SERVICE_NAME}-sc")
      client_alias {
        port = var.REDIS_CONFIG.PORT
      }
    }
  }

  depends_on = [var.redis_server_task_definitions_arn]
}


