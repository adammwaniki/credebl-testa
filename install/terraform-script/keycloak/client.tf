resource "keycloak_openid_client" "my_client" {
  realm_id          = keycloak_realm.my_realm.id
  client_id         = "adminClient"
  enabled           = true
  access_type       = "CONFIDENTIAL"
  client_authenticator_type = "client-secret"
  standard_flow_enabled = true
  service_accounts_enabled = true
  direct_access_grants_enabled = true
  valid_redirect_uris = [var.redirect_url]
  root_url = var.root_url
  web_origins = [var.root_url]
}

# Data source to fetch the realm-management client
data "keycloak_openid_client" "realm_management_client" {
  realm_id  = keycloak_realm.my_realm.id
  client_id = "realm-management"
}

resource "keycloak_openid_client_service_account_role" "create_client_role" {
  realm_id                = keycloak_realm.my_realm.id
  service_account_user_id = keycloak_openid_client.my_client.service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management_client.id
  role                    = "create-client"
}

resource "keycloak_openid_client_service_account_role" "manage_clients_role" {
  realm_id                = keycloak_realm.my_realm.id
  service_account_user_id = keycloak_openid_client.my_client.service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management_client.id
  role                    = "manage-clients"
}

resource "keycloak_openid_client_service_account_role" "query_clients_role" {
  realm_id                = keycloak_realm.my_realm.id
  service_account_user_id = keycloak_openid_client.my_client.service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management_client.id
  role                    = "query-clients"
}

resource "keycloak_openid_client_service_account_role" "view_clients_role" {
  realm_id                = keycloak_realm.my_realm.id
  service_account_user_id = keycloak_openid_client.my_client.service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management_client.id
  role                    = "view-clients"
}

resource "keycloak_openid_client_service_account_role" "manage_users_role" {
  realm_id                = keycloak_realm.my_realm.id
  service_account_user_id = keycloak_openid_client.my_client.service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management_client.id
  role                    = "manage-users"
}

resource "keycloak_openid_client_service_account_role" "query_users_role" {
  realm_id                = keycloak_realm.my_realm.id
  service_account_user_id = keycloak_openid_client.my_client.service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management_client.id
  role                    = "query-users"
}

resource "keycloak_openid_client_service_account_role" "view_users_role" {
  realm_id                = keycloak_realm.my_realm.id
  service_account_user_id = keycloak_openid_client.my_client.service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management_client.id
  role                    = "view-users"
}