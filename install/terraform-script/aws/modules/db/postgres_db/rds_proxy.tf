

resource "aws_kms_key" "kms_for_secrets" {
  description               = "KMS key for encrypting Secrets Manager secrets"
  key_usage                 = "ENCRYPT_DECRYPT"
  customer_master_key_spec  = "SYMMETRIC_DEFAULT"

  tags = {
    Name        = "${var.project_name}-${var.environment}-kms-for-secrets"
  }
}

# Secrets Manager to store DB credentials
resource "aws_secretsmanager_secret" "db_secrets" {
  for_each = local.db_configs

  name        = "${lower(replace("${var.project_name}-${var.environment}-${each.key}", "_", "-"))}-db-credentials"
  description = "Database credentials for ${lower(each.key)} in ${var.environment} environment"
  kms_key_id  = aws_kms_key.kms_for_secrets.id

  tags = {
    Name = "${var.project_name}-${var.environment}-${lower(each.key)}-db-secret"
  }
}

resource "aws_secretsmanager_secret_version" "db_secrets_version" {
  for_each = local.db_configs

  secret_id    = aws_secretsmanager_secret.db_secrets[each.key].id
  secret_string = jsonencode({
    username = each.value.username
    password = random_string.db_passwords[each.key].result
  })
}

# IAM Role for RDS Proxy
resource "aws_iam_role" "rds_proxy_role" {
  name = "${var.project_name}-${var.environment}-rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "rds.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-proxy-role"
  }
}

# IAM Policy for RDS Proxy Role
resource "aws_iam_policy" "secrets_access_policy" {
  name = "${var.project_name}-${var.environment}-secrets-access-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AccessSecretsManager",
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Resource = [
          for db_secret in keys(local.db_configs) : aws_secretsmanager_secret.db_secrets[db_secret].arn
        ]
      },
      {
        Sid    = "DecryptSecrets",
        Effect = "Allow",
        Action = "kms:Decrypt",
        Resource = aws_kms_key.kms_for_secrets.arn
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-secrets-access-policy"
  }
}

# Attach the policy to the IAM Role
resource "aws_iam_role_policy_attachment" "attach_secrets_policy" {
  role       = aws_iam_role.rds_proxy_role.name
  policy_arn = aws_iam_policy.secrets_access_policy.arn
}

# RDS Proxy
resource "aws_db_proxy" "rds_proxy" {
  for_each = local.db_configs

  name                   = "${lower(replace("${var.project_name}-${var.environment}-${each.key}", "_", "-"))}-db"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.rds_proxy_role.arn
  vpc_subnet_ids         = concat(var.private_db_subnet_ids, var.public_subnet_ids)
  vpc_security_group_ids = [each.value.rds_proxy_sg_ids]
  idle_client_timeout    = 300
  require_tls            = true

  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_secretsmanager_secret.db_secrets[each.key].arn
    iam_auth    = "DISABLED" # Enable if using IAM DB authentication
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${lower(each.key)}-proxy"
  }
}

# Attach databases to the RDS Proxy target group
resource "aws_db_proxy_target" "db_proxy_target" {
  for_each = local.db_configs

  db_proxy_name = aws_db_proxy.rds_proxy[each.key].name
  target_group_name = "default" # Use the default target group for the proxy

  # Attach an RDS instance or cluster
  db_instance_identifier =  "${lower(replace("${var.project_name}-${var.environment}-${each.key}", "_", "-"))}-db"
  # Or, if you're using an RDS cluster:
  # db_cluster_identifier = each.value.db_cluster_id
}
