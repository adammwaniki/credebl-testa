
data "aws_secretsmanager_secret" "secrete" {
  for_each = toset(keys(local.services_with_seed_key))

  name = each.value
}

data "aws_secretsmanager_secret_version" "secrets" {
  for_each = toset(keys(local.services_with_seed_key))

  secret_id = data.aws_secretsmanager_secret.secrete[each.key].id
}

resource "aws_s3_object" "api_gateway_env" {
  bucket  = var.env_file_bucket_id
  key     = "${var.environment}-API_GATEWAY.env"
  content = <<-EOT
    PLATFORM_PROFILE_MODE=${upper(var.environment)}
    API_GATEWAY_PROTOCOL=http
    API_GATEWAY_HOST=0.0.0.0
    API_GATEWAY_PORT=5000
    PLATFORM_NAME=${upper(var.project_name)}
    PROTOCOL=http
    TENANT_EMAIL_LOGO=credebl.jpg
    API_ENDPOINT=${local.api_gateway_service_connect}
    SOCKET_HOST=ws://${local.api_gateway_service_connect}
    NATS_URL=${join(", ", local.nats_url)}
    REDIS_HOST=${local.redis_service_connect}
    REDIS_PORT=${var.REDIS_CONFIG.PORT}
    SENDGRID_API_KEY=${var.SENDGRID_API_KEY}
    FRONT_END_URL=http://${var.alb_details["UI"].dns} 
    AGENT_PROTOCOL=http
    WALLET_STORAGE_HOST=${local.api_gateway_rds_proxy_credentials.endpoint}
    WALLET_STORAGE_PORT=${local.api_gateway_db_credentials.port}
    WALLET_STORAGE_USER=${local.api_gateway_db_credentials.username}
    WALLET_STORAGE_PASSWORD=${local.api_gateway_db_credentials.password}
    AGENT_HOST=ec2-user@3.110.168.41
    AWS_ACCOUNT_ID=${var.AWS_ACCOUNT_ID}
    PLATFORM_WALLET_NAME=platform-admin
    PLATFORM_WALLET_PASSWORD=${var.PLATFORM_WALLET_PASSWORD}
    PLATFORM_SEED=${var.platform_seed}
    S3_BUCKET_ARN=${var.env_file_bucket_arn}
    
    CRYPTO_PRIVATE_KEY=${var.crypto_private_key}
    PLATFORM_URL=http://${local.api_gateway_service_connect}
    AFJ_AGENT_SPIN_UP=/agent-provisioning/AFJ/scripts/start_agent_ecs.sh
    AFJ_AGENT_ENDPOINT_PATH=/agent-provisioning/AFJ/endpoints/
    PLATFORM_ID=1
    AFJ_VERSION=afj-0.4.2:latest
    PLATFORM_ADMIN_EMAIL=platform.admin@yopmail.com
    AFJ_AGENT_TOKEN_PATH=/agent-provisioning/AFJ/agent-config/token/
    AFJ_IMAGE_URL=public.ecr.aws/ayanworks-technologies/credebl:CREDO

    FIDO_API_ENDPOINT=${local.webauthn_service_connect}

    DATABASE_URL=postgres://${local.api_gateway_db_credentials.username}:${local.api_gateway_db_credentials.password}@${local.api_gateway_rds_proxy_credentials.endpoint}:${local.api_gateway_db_credentials.port}/platform
    POOL_DATABASE_URL=postgres://${local.api_gateway_db_credentials.username}:${local.api_gateway_db_credentials.password}@${local.api_gateway_rds_proxy_credentials.endpoint}:${local.api_gateway_db_credentials.port}/platform?pgbouncer=true
    PLATFORM_LOGO=CREDEBL_LOGO.svg
    POWERED_BY=Blockster Labs Pvt. Ltd.
    PLATFORM_WEB_URL=http://${var.alb_details["UI"].dns}
    POWERED_BY_URL=https://blockster.global
    UPLOAD_LOGO_HOST=${local.api_gateway_service_connect}
    API_GATEWAY_PROTOCOL_SECURE=http
    AWS_ORG_LOGO_BUCKET_NAME=${var.org_logo_bucket_id}
    OOB_BATCH_SIZE=10
    KEYCLOAK_DOMAIN=http://${var.alb_details["KEYCLOAK"].dns} 
    KEYCLOAK_ADMIN_URL=http://${var.alb_details["KEYCLOAK"].dns} 
    KEYCLOAK_MASTER_REALM=master
    KEYCLOAK_MANAGEMENT_CLIENT_ID=xxxxxxxxxx
    KEYCLOAK_MANAGEMENT_CLIENT_SECRET=xxxxxxxxx
    KEYCLOAK_REALM=credebl_platform
    AWS_S3_STOREOBJECT_REGION=${var.region}
    AWS_S3_STOREOBJECT_BUCKET=${var.link_bucket_id}
    SHORTENED_URL_DOMAIN=https://s3.${var.region}.amazonaws.com/${var.link_bucket_id}
    DEEPLINK_DOMAIN=https://${var.link_bucket_id}?url=
    PUBLIC_PLATFORM_SUPPORT_EMAIL=support@blockster.global
    PUBLIC_LOCALHOST_URL=http://localhost:5000
    PUBLIC_DEV_API_URL=http://${local.api_gateway_service_connect}
    MOBILE_APP_NAME=ADEYA SSI App
    MOBILE_APP=ADEYA
    PLAY_STORE_DOWNLOAD_LINK=https://play.google.com/store/apps/details?id=id.credebl.adeya&pli=1
    IOS_DOWNLOAD_LINK=https://apps.apple.com/in/app/adeya-ssi-wallet/id6463845498
    MOBILE_APP_DOWNLOAD_URL=https://blockster.global/products/adeya
    SCHEMA_FILE_SERVER_URL=${local.schema_file_service_connect}
    MAX_ORG_LIMIT=10
    SCHEMA_FILE_SERVER_TOKEN=xxxxxxxx
    GEO_LOCATION_MASTER_DATA_IMPORT_SCRIPT=/prisma/scripts/geo_location_data_import.sh
    UPDATE_CLIENT_CREDENTIAL_SCRIPT=/prisma/scripts/update_client_credential_data.sh
    ENABLE_CORS_IP_LIST=http://localhost:3000,http://localhost:5000,http://${var.alb_details["KEYCLOAK"].dns},http://${var.alb_details["UI"].dns} 
    NEW_PAYLOAD_SIZE_LIMIT=5MB
    KEYCLOAK_PASSWORD_MIN_SIZE=8
    # Dynamic secrets for services
    %{for service, _ in local.services_with_seed_key}
    ${service}=${jsondecode(data.aws_secretsmanager_secret_version.secrets[service].secret_string)[service]}
    %{endfor}
  EOT
}
