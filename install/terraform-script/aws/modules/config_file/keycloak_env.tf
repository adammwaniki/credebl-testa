resource "aws_s3_object" "keycloak_env" {
  bucket = var.env_file_bucket_id
  key    = "${var.environment}-KEYCLOAK.env"
  content = <<-EOT
    KEYCLOAK_ADMIN=admin
    KEYCLOAK_ADMIN_PASSWORD=admin
    KC_HTTP_ENABLED=true
    KC_DB=postgres
    KC_DB_URL=jdbc:postgresql://${local.keycloak_rds_proxy_credentials.endpoint}:${local.keycloak_db_credentials.port}/${local.keycloak_db_credentials.db_name}
    KC_DB_USERNAME=${local.keycloak_db_credentials.username}
    KC_DB_PASSWORD=${local.keycloak_db_credentials.password}

    KC_DB_URL_PORT=${local.keycloak_db_credentials.port}
    PROXY_ADDRESS_FORWARDING=true

    KC_HOSTNAME_ADMIN_URL=http://${var.alb_details["KEYCLOAK"].dns}/
    KC_HOSTNAME_URL=http://${var.alb_details["KEYCLOAK"].dns}/

    KC_PROXY=none
    KC_HOSTNAME_STRICT=false
    KC_LOG=console
    KC_HOSTNAME_STRICT_HTTPS=false

    KC_HTTPS_ENABLED=false

    ./kcadm.sh config credentials --server http://0.0.0.0:8080 --realm master -user admin
    ./kcadm.sh update realms/master -s sslRequired=NONE
  EOT
}


