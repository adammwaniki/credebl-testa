# ALB Security Group for each service with port
resource "aws_security_group" "ALB_SG" {
  for_each = zipmap([for s in var.SERVICE_CONFIG.WITH_PORT : s.SERVICE_NAME], [for s in var.SERVICE_CONFIG.WITH_PORT : s.PORT])

  name   = "${var.project_name}_${var.environment}-${each.key}_ALB_SG"
  vpc_id = var.vpc_id

  dynamic "ingress" {
    for_each = toset([80, 443])
    content {
      description = "${each.key} ALB port access"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all traffic
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    name = "${var.project_name}_${var.environment}-${each.key}_ALB_SG"
  }
}

# ALB Security Group for schema file  service with port
resource "aws_security_group" "SCHEMA_FILE_SERVICE_ALB_SG" {
  name   = "${var.project_name}_${var.environment}-${var.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME}_ALB_SG"
  vpc_id = var.vpc_id

  dynamic "ingress" {
    for_each = toset([80, 443])
    content {
      description = "${var.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME} ALB port access"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all traffic
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}_${var.environment}-${var.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME}_ALB_SG"
  }
}

# Security group for the application, with ingress rules for each app service
resource "aws_security_group" "APP_SG" {
  for_each = zipmap([for s in var.SERVICE_CONFIG.WITH_PORT : s.SERVICE_NAME], [for s in var.SERVICE_CONFIG.WITH_PORT : s.PORT])

  name   = "${var.project_name}_${var.environment}-${each.key}_APP_SG"
  vpc_id = var.vpc_id

  ingress {
    description     = "${each.key} App port access"
    from_port       = each.value # Application's own port
    to_port         = each.value
    protocol        = "tcp"
    security_groups = [aws_security_group.ALB_SG[each.key].id] # Ensure each.key exists in ALB_SG
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all traffic
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}_${var.environment}-${each.key}_APP_SG"
  }
}


# Security group for the database, only for services with a DB_PORT
resource "aws_security_group" "RDS_PROXY_SG" {
  for_each = { for s in var.SERVICE_CONFIG.WITH_PORT : s.SERVICE_NAME => s.DB_PORT if s.DB_PORT != null }

  name   = "${var.project_name}_${var.environment}-${each.key}_RDS_PROXY_SG"
  vpc_id = var.vpc_id

  ingress {
    description     = "${each.key} DB port access"
    from_port       = each.value
    to_port         = each.value
    protocol        = "tcp"
    security_groups = [aws_security_group.APP_SG[each.key].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all traffic
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}_${var.environment}-${each.key}_DB_SG"
  }
}


# Security group for the database, only for services with a DB_PORT
resource "aws_security_group" "DB_SG" {
  for_each = { for s in var.SERVICE_CONFIG.WITH_PORT : s.SERVICE_NAME => s.DB_PORT if s.DB_PORT != null }

  name   = "${var.project_name}_${var.environment}-${each.key}_DB_SG"
  vpc_id = var.vpc_id

  ingress {
    description     = "${each.key} DB port access"
    from_port       = each.value
    to_port         = each.value
    protocol        = "tcp"
    security_groups = [aws_security_group.APP_SG[each.key].id]
  }
  # Allow access from RDS Proxy SG
  ingress {
    description     = "${each.key} DB port access from RDS Proxy SG"
    from_port       = each.value
    to_port         = each.value
    protocol        = "tcp"
    security_groups = [aws_security_group.RDS_PROXY_SG[each.key].id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all traffic
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}_${var.environment}-${each.key}_DB_SG"
  }
}


# Define Security Group for NATS ALB with conditional count based on the environment
resource "aws_security_group" "NATS_ALB_SG" {
  count = lower(var.environment) != "prod" ? 1 : 3

  name   = "${var.project_name}_${var.environment}_NATS_ALB_SG_${count.index + 1}"
  vpc_id = var.vpc_id

  # Dynamic ingress rule to allow traffic on ports 80 and 443
  dynamic "ingress" {
    for_each = toset([80, 443])
    content {
      description = "Allow ${var.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME} ALB port access"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Egress rule allowing all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all traffic
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}_${var.environment}_NATS_ALB_SG_${count.index + 1}"
  }
}



# Define Security Group for NATS with conditional count based on the environment
resource "aws_security_group" "NATS_SG" {
  count = lower(var.environment) == "dev" ? 1 : 3

  name   = "${var.project_name}_${var.environment}_NATS_SG_${count.index + 1}"
  vpc_id = var.vpc_id

  # Ingress rule for allowing traffic from the ALB security group
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1" # Allow all traffic
    security_groups = [aws_security_group.NATS_ALB_SG[count.index].id]
  }
  ingress {
    from_port   = 4245
    to_port     = 4245
    protocol    = "tcp" # Allow all traffic
    cidr_blocks = ["0.0.0.0/0"]

  }

  # Egress rule to allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all traffic
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}_${var.environment}_NATS_SG_${count.index + 1}"
  }
}




resource "aws_security_group" "SCHEMA_FILE_SERVICE_SG" {
  name   = "${var.project_name}_${var.environment}_SCHEMA_FILE_SERVICE_SG"
  vpc_id = var.vpc_id

  ingress {
    description     = "Schema file server port ${var.SCHEMA_FILE_SERVICE_CONFIG.PORT} access"
    from_port       = var.SCHEMA_FILE_SERVICE_CONFIG.PORT
    to_port         = var.SCHEMA_FILE_SERVICE_CONFIG.PORT
    protocol        = "tcp"
    security_groups = [aws_security_group.SCHEMA_FILE_SERVICE_ALB_SG.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all traffic
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}_${var.environment}_SCHEMA_FILE_SERVICE_SG"
  }
}



resource "aws_security_group" "REDIS_SG" {
  name   = "${var.project_name}_${var.environment}_REDIS_SG"
  vpc_id = var.vpc_id

  ingress {
    description     = "EFS port ${local.REDIS_CONFIG.SERVICE_NAME} access for API_GATEWAY"
    from_port       = local.REDIS_CONFIG.PORT
    to_port         = local.REDIS_CONFIG.PORT
    protocol        = "tcp"
    security_groups = [aws_security_group.APP_SG["API_GATEWAY"].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all traffic
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}_${var.environment}_REDIS_SG"
  }
}

# Define Security Group for EFS with inbound access for API_GATEWAY and NATS SG
resource "aws_security_group" "EFS_SG" {
  name   = "${var.project_name}_${var.environment}_EFS_SG"
  vpc_id = var.vpc_id

  ingress {
    description = "EFS port ${local.EFS_PORT} access for API_GATEWAY"
    from_port   = local.EFS_PORT
    to_port     = local.EFS_PORT
    protocol    = "tcp"
    security_groups = flatten([
      [aws_security_group.APP_SG["API_GATEWAY"].id, aws_security_group.SCHEMA_FILE_SERVICE_SG.id],
      lower(var.environment) != "dev" ? [for i in aws_security_group.NATS_SG : i.id] : []
    ])
  }
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all traffic
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # Allow all traffic
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}_${var.environment}_EFS_SG"
  }
}
