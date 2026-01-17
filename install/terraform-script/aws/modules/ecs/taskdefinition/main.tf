resource "aws_ecs_task_definition" "with_port_task_definitions" {
  for_each               = { for idx, service in var.SERVICE_CONFIG.WITH_PORT : service.SERVICE_NAME => service }
  family                 = upper("${var.project_name}_${var.environment}_${each.value.SERVICE_NAME}_TASKDEFINITION")
  network_mode           = "awsvpc"
  cpu                    = "1024"
  memory                 = "2048"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn     = var.ecs_tasks_execution_role_arn
  task_role_arn          = var.ecs_tasks_role_arn

  container_definitions = jsonencode([
    {
      name      = each.value.SERVICE_NAME
      image     = "${local.image_url}:${each.value.SERVICE_NAME}_SERVICE"
      cpu       = 1024
      memory    = 2048
      essential = true

      command   = each.value.SERVICE_NAME == "KEYCLOAK" ? ["start"] : null

      environmentFiles = [
        {
          value = "${var.env_file_bucket_arn}/${var.environment}-${each.value.SERVICE_NAME}.env"
          type  = "s3"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}_${var.environment}_${each.value.SERVICE_NAME}"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group"  = "true"
        }
      }

      runtime_platform = {
        cpuArchitecture       = "X86_64"
        operatingSystemFamily = "LINUX"
      }
    
      portMappings = [
        {
          containerPort = each.value.PORT # Replace with your UI's port
          hostPort      = each.value.PORT
          protocol      = "tcp",
          name          = lower("${each.value.SERVICE_NAME}-${each.value.PORT}-tcp")
          appProtocol   = "http"
        }
      ]
    }
  ])
}

resource "aws_ecs_task_definition" "without_port_task_definitions" {
  for_each               = toset(local.SERVICE_CONFIG.WITHOUT_PORT)
  family                 = upper("${var.project_name}_${var.environment}_${each.value}_TASKDEFINITION")
  network_mode           = "awsvpc"
  cpu                    = "1024"
  memory                 = "2048"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn     = var.ecs_tasks_execution_role_arn
  task_role_arn          = var.ecs_tasks_role_arn

  container_definitions = jsonencode([
    {
      name      = each.value
      image     = "${local.image_url}:${each.value}"
     cpu       = 1024
      memory    = 2048
      essential = true

      environmentFiles = [
        {
          value = "${var.env_file_bucket_arn}/${var.environment}-${each.value}.env"
          type  = "s3"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}_${var.environment}_${each.value}"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group"  = "true"
        }
      }

      runtime_platform = {
        cpuArchitecture       = "X86_64"
        operatingSystemFamily = "LINUX"
      }
    }
  ])
}


resource "aws_ecs_task_definition" "schema_file_server_task_definitions" {
  family                   = upper("${var.project_name}_${var.environment}_${var.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME}_TASKDEFINITION")
  network_mode             = "awsvpc"
  cpu                    = "1024"
  memory                 = "2048"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = var.ecs_tasks_execution_role_arn
  task_role_arn            = var.ecs_tasks_role_arn

  container_definitions = jsonencode([
    {
      name      = var.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME
      image     = "${local.image_url}:${local.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME}"
     cpu       = 1024
      memory    = 2048
      essential = true

      environmentFiles = [
        {
          value = "${var.env_file_bucket_arn}/${var.environment}-${local.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME}.env"
          type  = "s3"
        }
      ]
      
      mountPoints = [
        {
          sourceVolume  = "${local.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME}_VOLUME"
          containerPath = "/app/schemas"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}_${var.environment}_${local.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME}"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group"  = "true"
        }
      }

      runtime_platform = {
        cpuArchitecture       = "X86_64"
        operatingSystemFamily = "LINUX"
      }
    
      portMappings = [
        {
          containerPort = local.SCHEMA_FILE_SERVICE_CONFIG.PORT
          hostPort      = local.SCHEMA_FILE_SERVICE_CONFIG.PORT
          protocol      = "tcp",
          name          = lower("${local.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME}-${local.SCHEMA_FILE_SERVICE_CONFIG.PORT}-tcp")
          appProtocol   = "http"
        }
      ]
    }
  ])

  volume {
    name = "${var.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME}_VOLUME"
    efs_volume_configuration {
      file_system_id = var.schema_file_service_efs_id
      root_directory = "/"
    }
  }
}



resource "aws_ecs_task_definition" "agent_provisioning_service_task_definitions" {
  family                 = upper("${var.project_name}_${var.environment}_${var.AGENT_PROVISIONING_SERVICE.SERVICE_NAME}_TASKDEFINITION")
  network_mode           = "awsvpc"
  cpu                    = "1024"
  memory                 = "2048"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn     = var.ecs_tasks_execution_role_arn
  task_role_arn          = var.ecs_tasks_role_arn

  container_definitions = jsonencode([
    {
      name      = var.AGENT_PROVISIONING_SERVICE.SERVICE_NAME
      image     = "${local.image_url}:${var.AGENT_PROVISIONING_SERVICE.SERVICE_NAME}"
      cpu       = 1024
      memory    = 2048
      essential = true

      environmentFiles = [
        {
          value = "${var.env_file_bucket_arn}/${var.environment}-API_GATEWAY.env"
          type  = "s3"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "agent-config"
          containerPath = "/app/agent-provisioning/AFJ/agent-config"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}_${var.environment}_${var.AGENT_PROVISIONING_SERVICE.SERVICE_NAME}"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group"  = "true"
        }
      }

      runtime_platform = {
        cpuArchitecture       = "X86_64"
        operatingSystemFamily = "LINUX"
      }
    }
  ])
  volume {
    name = "agent-config"
    efs_volume_configuration {
      file_system_id = var.credo_efs_id
      root_directory = "/"
    }
  }

}

resource "aws_ecs_task_definition" "nats_service_task_definitions" {
  count                    = lower(var.environment) != "prod" ? 1 : 3
  family                   = upper("${var.project_name}_${var.environment}_${var.SERVICE_CONFIG.NATS.SERVICE_NAME}_${count.index+1}_TASKDEFINITION")
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = var.ecs_tasks_execution_role_arn
  task_role_arn            = var.ecs_tasks_role_arn

  container_definitions = jsonencode([
    {
      name      = "${var.SERVICE_CONFIG.NATS.SERVICE_NAME}_${count.index+1}"
      image     = "nats:2.6.4"
      cpu       = 1024
      memory    = 2048
      essential = true
      command   = [
                "-c",
                "/config/nats.config"
            ]
      environmentFiles = []

      mountPoints = [
        {
          sourceVolume  = "nats-config"
          containerPath = "/config"
          readOnly      = false
        }
      ]

      # Dynamically creating portMappings for each port in the NATS.PORT list
      portMappings = [
        for port in var.SERVICE_CONFIG.NATS.PORT : {
          containerPort = port
          hostPort      = port
          protocol      = "tcp",
          name          = lower("${var.SERVICE_CONFIG.NATS.SERVICE_NAME}-${count.index+1}-${port}-tcp")
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}_${var.environment}_${var.SERVICE_CONFIG.NATS.SERVICE_NAME}_${count.index+1}"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group"  = "true"
        }
      }

      runtime_platform = {
        cpuArchitecture       = "X86_64"
        operatingSystemFamily = "LINUX"
      }
      
      # command = [var.SERVICE_CONFIG.NATS.container_cmd]
    }
  ])

  volume {
    name = "nats-config"
    efs_volume_configuration {
      file_system_id = var.nats_efs_id
      root_directory = "/"
    }
  }
}


resource "aws_ecs_task_definition" "redis_server_task_definitions" {
  family                   = upper("${var.project_name}_${var.environment}_${var.REDIS_CONFIG.SERVICE_NAME}_TASKDEFINITION")
  network_mode             = "awsvpc"
  cpu                    = "1024"
  memory                 = "2048"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = var.ecs_tasks_execution_role_arn
  task_role_arn            = var.ecs_tasks_role_arn

  container_definitions = jsonencode([
    {
      name      = var.REDIS_CONFIG.SERVICE_NAME
      image     = "redis"
      cpu       = 1024
      memory    = 2048
      essential = true

      environmentFiles = []
      
      mountPoints = [
        {
          sourceVolume  = "${var.REDIS_CONFIG.SERVICE_NAME}_VOLUME"
          containerPath = "/data"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.project_name}_${var.environment}_${var.REDIS_CONFIG.SERVICE_NAME}"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
          "awslogs-create-group"  = "true"
        }
      }

      runtime_platform = {
        cpuArchitecture       = "X86_64"
        operatingSystemFamily = "LINUX"
      }
    
      portMappings = [
        {
          containerPort = var.REDIS_CONFIG.PORT
          hostPort      = var.REDIS_CONFIG.PORT
          protocol      = "tcp",
          name          = lower("${var.REDIS_CONFIG.SERVICE_NAME}-${var.REDIS_CONFIG.PORT}-tcp")
          appProtocol   = "http"
        }
      ]
    }
  ])

  volume {
    name = "${var.REDIS_CONFIG.SERVICE_NAME}_VOLUME"
    efs_volume_configuration {
      file_system_id = var.redis_efs_id
      root_directory = "/"
    }
  }
}