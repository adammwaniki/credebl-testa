resource "aws_efs_file_system" "credo_efs" {
  creation_token   = "${var.environment}-${var.project_name}-credo-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = "true"
  tags = {
    Name = "${var.environment}-${var.project_name}-CREDO-EFS"
  }
}


resource "aws_efs_mount_target" "credo_efs_mt" {
  count           = length(var.private_app_subnet_ids)
  file_system_id  = aws_efs_file_system.credo_efs.id
  subnet_id       = var.private_app_subnet_ids[count.index]
  security_groups = [var.efs_sg_id] # Adjust as needed
}


resource "aws_efs_file_system" "nats_efs" {
  creation_token   = "${var.environment}-${var.project_name}-nats-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = "true"
  tags = {
    Name = "${var.environment}-${var.project_name}-NATS-EFS"
  }
}


resource "aws_efs_mount_target" "nats_efs_mt" {
  count = length(var.private_app_subnet_ids)

  file_system_id  = aws_efs_file_system.nats_efs.id
  subnet_id       = var.private_app_subnet_ids[count.index]
  security_groups = [var.efs_sg_id] # Adjust as needed
}
#nats access point for lambda
resource "aws_efs_access_point" "nats_access_point" {
  file_system_id = aws_efs_file_system.nats_efs.id
  root_directory {
    path = "/" # Root directory

    creation_info {
      owner_gid   = 0
      owner_uid   = 0
      permissions = "777"
    }

  }
  posix_user {
    gid = 0
    uid = 0
  }
}

resource "aws_efs_file_system" "schema_file_efs" {
  creation_token   = "${var.environment}-${var.project_name}-schema-file-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = "true"
  tags = {
    Name = "${var.environment}-${var.project_name}-SCHEMA-FILE-EFS"
  }
}


resource "aws_efs_mount_target" "schema_file_efs_mt" {
  count           = length(var.private_app_subnet_ids)
  file_system_id  = aws_efs_file_system.schema_file_efs.id
  subnet_id       = var.private_app_subnet_ids[count.index]
  security_groups = [var.efs_sg_id] # Adjust as needed
}

resource "aws_efs_file_system" "redis_efs" {
  creation_token   = "${var.environment}-${var.project_name}-redis-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = "true"
  tags = {
    Name = "${var.environment}-${var.project_name}-REDIS-EFS"
  }
}


resource "aws_efs_mount_target" "redis_efs_mt" {
  count           = length(var.private_app_subnet_ids)
  file_system_id  = aws_efs_file_system.redis_efs.id
  subnet_id       = var.private_app_subnet_ids[count.index]
  security_groups = [var.efs_sg_id] # Adjust as needed
}

