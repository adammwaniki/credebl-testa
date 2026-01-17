locals {
  image_tags = toset(concat(
    [for s in var.SERVICE_CONFIG.WITH_PORT : s.SERVICE_NAME],
    var.SERVICE_CONFIG.WITHOUT_PORT
  ))
}
