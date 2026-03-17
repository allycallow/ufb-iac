# TODO: UPDATE SYNTAX OF SSM NAME TO ufb/production/{name}

resource "random_password" "api_key" {
  length           = 20
  special          = true
  override_special = "_%@"
}

resource "random_password" "recommendations" {
  length           = 20
  special          = true
  override_special = "_%@"
}

resource "random_password" "notifications" {
  length           = 20
  special          = true
  override_special = "_%@"
}

resource "random_password" "events" {
  length           = 20
  special          = true
  override_special = "_%@"
}

resource "aws_ssm_parameter" "media_private_key" {
  name  = "/ufb/${terraform.workspace}/media-private-key"
  type  = "String"
  value = tls_private_key.media.private_key_pem
}

resource "aws_ssm_parameter" "notifications_api_key" {
  name  = "/ufb/${terraform.workspace}/notifications-api-key"
  type  = "String"
  value = random_password.notifications.result
}

resource "aws_ssm_parameter" "events_api_key" {
  name  = "/ufb/${terraform.workspace}/events-api-key"
  type  = "String"
  value = random_password.events.result
}

output "media_private_key_secret_name" {
  value = aws_ssm_parameter.media_private_key.name
}

output "notifications_api_key_ssm_name" {
  value = aws_ssm_parameter.notifications_api_key.name
}
