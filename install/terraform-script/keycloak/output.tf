data "keycloak_openid_client" "admin_client" {
  realm_id = keycloak_realm.my_realm.id
  client_id = "adminClient"
  depends_on = [keycloak_openid_client.my_client]
}

output "admin_client_secret" {
  value = data.keycloak_openid_client.admin_client.client_secret
  sensitive = true
}


resource "local_file" "env_file" {
  filename = "secret.env"
  content  = <<EOT
ADMIN_CLIENT_SECRET=${data.keycloak_openid_client.admin_client.client_secret}
EOT
}
