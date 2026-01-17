# Create an ALB for each service with a port in SERVICE_CONFIG
resource "aws_lb" "alb" {
  for_each           = { for service in var.SERVICE_CONFIG.WITH_PORT : service.SERVICE_NAME => service }
  name               = upper(replace("${var.environment}-${var.project_name}-${each.key}-alb", "_", "-"))
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_ids[each.key]] # Updated this line to access the security group ID directly
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}-alb"
  }
}

# Create target groups for each service with ports defined in SERVICE_CONFIG
resource "aws_lb_target_group" "app_tg" {
  for_each = { for service in var.SERVICE_CONFIG.WITH_PORT : service.SERVICE_NAME => service }

  name        = upper(replace("${var.environment}-${var.project_name}-${each.key}-tg", "_", "-"))
  target_type = "ip"
  port        = each.value.PORT
  protocol    = "HTTP"
  vpc_id      = var.vpc_id

  # Configure health checks using each service's health check settings
  health_check {
    path                = each.value.health_check.path
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
    matcher             = each.value.health_check.matcher
  }

  tags = {
    Name = "${var.environment}-${var.project_name}-${each.value.SERVICE_NAME}-tg"
  }
}

# HTTP Listener for each ALB (redirects HTTP to HTTPS)
resource "aws_lb_listener" "http_listener" {
  for_each          = aws_lb.alb
  load_balancer_arn = each.value.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg[each.key].arn # Forward to the corresponding target group
  }
}


# Create an ALB for the schema file server
resource "aws_lb" "schema_file_alb" {
  name               = upper(replace("${var.environment}-${var.project_name}-schema-file-alb", "_", "-"))
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.schema_file_service_alb_sg_id] # Use the security group for the schema file server
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-${var.environment}-schema-file-alb"
  }
}

# Create target group for the schema file server
resource "aws_lb_target_group" "schema_file_tg" {
  name        = upper(replace("${var.environment}-${var.project_name}-schema-file-tg", "_", "-"))
  target_type = "ip"
  port        = var.SCHEMA_FILE_SERVICE_CONFIG.PORT # Using the port defined in the variable
  protocol    = "HTTP"
  vpc_id      = var.vpc_id

  # Configure health checks for the schema file server
  health_check {
    path                = var.SCHEMA_FILE_SERVICE_CONFIG.health_check.path
    interval            = var.SCHEMA_FILE_SERVICE_CONFIG.health_check.interval
    timeout             = var.SCHEMA_FILE_SERVICE_CONFIG.health_check.timeout
    healthy_threshold   = var.SCHEMA_FILE_SERVICE_CONFIG.health_check.healthy_threshold
    unhealthy_threshold = var.SCHEMA_FILE_SERVICE_CONFIG.health_check.unhealthy_threshold
    matcher             = var.SCHEMA_FILE_SERVICE_CONFIG.health_check.matcher
  }

  tags = {
    Name = "${var.environment}-${var.project_name}-schema-file-tg"
  }
}

# HTTP Listener for the schema file server ALB
resource "aws_lb_listener" "schema_file_http_listener" {
  load_balancer_arn = aws_lb.schema_file_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.schema_file_tg.arn # Forward to the schema file target group
  }
}

#nats nlb

resource "aws_lb" "nats_nlb" {
  name               = upper(replace("${var.environment}-${var.project_name}-${var.SERVICE_CONFIG.NATS.SERVICE_NAME}-nlb", "_", "-"))
  internal           = false
  load_balancer_type = "network"
  security_groups    = values(var.nats_alb_security_group_ids)
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name = "${var.environment}-${var.project_name}-nats-nlb"
  }
}


resource "aws_lb_target_group" "nats_tg" {
  count       = length(var.nats_security_group_ids) # Number of target groups based on the security group count
  name        = upper("${var.project_name}-${var.environment}-nats-tg-${count.index + 1}")
  port        = var.SERVICE_CONFIG.NATS.PORT[0]
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "traffic-port"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.environment}-${var.project_name}-nats-tg-${count.index + 1}"
  }
}

#nats tg
resource "aws_lb_listener" "nats_listener" {
  count             = length(aws_lb_target_group.nats_tg)
  load_balancer_arn = aws_lb.nats_nlb.arn
  port              = var.SERVICE_CONFIG.NATS.PORT[count.index]
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nats_tg[count.index].arn
  }
}
