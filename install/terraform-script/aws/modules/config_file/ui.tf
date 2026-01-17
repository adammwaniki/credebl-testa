resource "aws_s3_object" "ui_env" {
  bucket  = var.env_file_bucket_id
  key     = "${var.environment}-UI.env"
  content = <<-EOT
    PUBLIC_BASE_URL=http://${local.api_gateway_service_connect}  # api-gateway url

PUBLIC_CRYPTO_PRIVATE_KEY=${var.crypto_private_key}  # cpoy crypto key from banckend
PUBLIC_PLATFORM_NAME=upper(var.project_name)
PUBLIC_PLATFORM_LOGO="https://${var.org_logo_bucket_dns}/assets/logo.png"
PUBLIC_POWERED_BY= upper(var.project_name)
PUBLIC_PLATFORM_WEB_URL=http://${var.alb_details["UI"].dns} 
PUBLIC_POWERED_BY_URL=http://${var.alb_details["UI"].dns} 
PUBLIC_PLATFORM_DOCS_URL=""
PUBLIC_PLATFORM_GIT=""
PUBLIC_PLATFORM_SUPPORT_EMAIL=""
PUBLIC_PLATFORM_SUPPORT_INVITE=""
PUBLIC_PLATFORM_TWITTER_URL=""
PUBLIC_PLATFROM_DISCORD_SUPPORT=""
PUBLIC_SHOW_NAME_AS_LOGO=true

#keyclaok details
PUBLIC_KEYCLOAK_MANAGEMENT_CLIENT_ID=xxxxxxxxxx
PUBLIC_KEYCLOAK_MANAGEMENT_CLIENT_SECRET=xxxxxxxxx 

#whitelist URl to access frontend

PUBLIC_ALLOW_DOMAIN=https://s3.${var.region}.amazonaws.com/${var.link_bucket_id} ${var.org_logo_bucket_dns} http://${local.api_gateway_service_connect}  https://cdnjs.cloudflare.com https://tailwindcss.com https://www.ayanworks.com https://fonts.googleapis.com https://fonts.gstatic.com https://avatars.githubusercontent.com  https://dev-org-logo.s3.ap-south-1.amazonaws.com https://flowbite-admin-dashboard.vercel.app/ http://localhost:3000 http://localhost:8085 
  EOT
}

