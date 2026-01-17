
# Output Service Connect endpoints for withport_server services
output "withport_server_service_connect_endpoints_13" {
  value = flatten([
    for service in var.SERVICE_CONFIG.WITH_PORT : 
      "http://${lower(service.SERVICE_NAME)}-sc.${aws_service_discovery_http_namespace.cluster_namespace.name}:${service.PORT}"
  ])
  description = "Service Connect endpoints for withport_server services"
}



# Output Service Connect endpoints for schema_file_server service
output "schema_file_service_connect_endpoint" {
  value = "http://${lower(var.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME)}-sc.${aws_service_discovery_http_namespace.cluster_namespace.name}:${var.SCHEMA_FILE_SERVICE_CONFIG.PORT}"
  description = "Service Connect endpoint for schema file service"
}


# Output Service Connect endpoints for redis_server
output "redis_service_connect_endpoint" {
  value = "http://${lower(var.REDIS_CONFIG.SERVICE_NAME)}-sc.${aws_service_discovery_http_namespace.cluster_namespace.name}:${var.REDIS_CONFIG.PORT}"
  description = "Service Connect endpoint for schema file service"
}


# Output Service Connect endpoints for api_gateway_server
output "api_gateway_service_connect_endpoint" {
  value = "http://${lower(var.SERVICE_CONFIG.WITH_PORT[0].SERVICE_NAME)}-sc.${aws_service_discovery_http_namespace.cluster_namespace.name}:${var.SERVICE_CONFIG.WITH_PORT[1].PORT}"
  description = "Service Connect endpoint for Keycloak service"
}

# Output Service Connect endpoints for keycloak_server
output "keycloak_service_connect_endpoint" {
  value = "http://${lower(var.SERVICE_CONFIG.WITH_PORT[1].SERVICE_NAME)}-sc.${aws_service_discovery_http_namespace.cluster_namespace.name}:${var.SERVICE_CONFIG.WITH_PORT[1].PORT}"
  description = "Service Connect endpoint for Keycloak service"
}


# Output Service Connect endpoints for mediator_server
output "mediator_service_connect_endpoint" {
  value = "http://${lower(var.SERVICE_CONFIG.WITH_PORT[2].SERVICE_NAME)}-sc.${aws_service_discovery_http_namespace.cluster_namespace.name}:${var.SERVICE_CONFIG.WITH_PORT[1].PORT}"
  description = "Service Connect endpoint for Keycloak service"
}

# Output Service Connect endpoints for webauthn_server
output "webauthn_service_connect_endpoint" {
  value = "http://${lower(var.SERVICE_CONFIG.WITH_PORT[3].SERVICE_NAME)}-sc.${aws_service_discovery_http_namespace.cluster_namespace.name}:${var.SERVICE_CONFIG.WITH_PORT[1].PORT}"
  description = "Service Connect endpoint for Keycloak service"
}









