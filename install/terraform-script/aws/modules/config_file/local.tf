locals {

  api_gateway_service_connect = "${lower(var.SERVICE_CONFIG.WITH_PORT[0].SERVICE_NAME)}-sc.${lower(replace("${var.environment}-${var.project_name}-namespace", "_", "-"))}:${var.SERVICE_CONFIG.WITH_PORT[0].PORT}"
  redis_service_connect = "http://${lower(var.REDIS_CONFIG.SERVICE_NAME)}-sc.${lower(replace("${var.environment}-${var.project_name}-namespace", "_", "-"))}:${var.REDIS_CONFIG.PORT}"
  keyclock_service_connect = "http://${lower(var.SERVICE_CONFIG.WITH_PORT[1].SERVICE_NAME)}-sc.${lower(replace("${var.environment}-${var.project_name}-namespace", "_", "-"))}:${var.SERVICE_CONFIG.WITH_PORT[1].PORT}"
  schema_file_service_connect = "http://${lower(var.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME)}-sc.${lower(replace("${var.environment}-${var.project_name}-namespace", "_", "-"))}:${var.SERVICE_CONFIG.WITH_PORT[1].PORT}"
  webauthn_service_connect = "http://${lower(var.SERVICE_CONFIG.WITH_PORT[3].SERVICE_NAME)}-sc.${lower(replace("${var.environment}-${var.project_name}-namespace", "_", "-"))}:${var.SERVICE_CONFIG.WITH_PORT[1].PORT}"
}

locals {
  count    = var.nats_count
  nats_url = [
    for i in range(local.count) : format(
      "nats://nats-%d-%d.%s-namespace:%d",
      i + 1,      
      var.SERVICE_CONFIG.NATS.PORT[0],                                     # Index for each NATS instance (1, 2, ...)
      lower(replace("${var.environment}-${var.project_name}", "_", "-")),  # Cluster name with "_" replaced by "-"
      var.SERVICE_CONFIG.NATS.PORT[0]             # The desired port from the service config
    )
  ]
}

locals {
  cluster_count    = var.nats_count
  cluster_ips = [
    for i in range(local.cluster_count) : format(
      "nats://nats-%d-%d.%s-namespace:%d",
      i + 1,  
      var.SERVICE_CONFIG.NATS.PORT[3],                                         # Index for each NATS instance (1, 2, ...)
      lower(replace("${var.environment}-${var.project_name}", "_", "-")),  # Cluster name with "_" replaced by "-"
      var.SERVICE_CONFIG.NATS.PORT[3]             # The desired port from the service config
    )
  ]
}

locals {
  api_gateway_db_credentials = var.database_info_by_service["api_gateway"]
  keycloak_db_credentials    = var.database_info_by_service["keycloak"]
  mediator_db_credentials    = var.database_info_by_service["mediator"]
}

locals {
  api_gateway_rds_proxy_credentials = var.rds_proxy_info_by_service["api_gateway"]
  keycloak_rds_proxy_credentials    = var.rds_proxy_info_by_service["keycloak"]
  mediator_rds_proxy_credentials    = var.rds_proxy_info_by_service["mediator"]
}



locals {
  alb_dns_by_service = {
    for service_name, alb_dns in var.alb_dns_by_service : service_name => alb_dns
  }
}

# Add _SEED_KEY postfix to each service name
locals {
  services_with_seed_key = { for service in var.nats_seed_key : "${service}_NKEY_SEED" => "${service}_NKEY_SEED" }
}
