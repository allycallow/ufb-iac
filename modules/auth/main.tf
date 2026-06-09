resource "aws_cognito_user_pool" "pool" {
  name                     = var.name
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  lambda_config {
    post_confirmation = "arn:aws:lambda:eu-west-2:${var.account_id}:function:production-ufb-post-confirmation"
    pre_sign_up       = "arn:aws:lambda:eu-west-2:${var.account_id}:function:production-ufb-pre-signup"
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  schema {
    name                     = "given_name"
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    required                 = true

    string_attribute_constraints {
      min_length = 0
      max_length = 32
    }
  }

  schema {
    name                     = "family_name"
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    required                 = true

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                     = "gender"
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    required                 = false

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  schema {
    name                     = "birthdate"
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    required                 = false

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name                = var.name
  user_pool_id        = aws_cognito_user_pool.pool.id
  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_USER_PASSWORD_AUTH"]

  callback_urls = [
    "https://local.${var.domain}:3001/",
    "https://${terraform.workspace}.${var.domain}/",
    "https://${var.domain}/"
  ]
  logout_urls = [
    "https://local.${var.domain}:3001/",
    "https://${terraform.workspace}.${var.domain}/",
    "https://${var.domain}/"
  ]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "profile", "openid", "aws.cognito.signin.user.admin"]

  supported_identity_providers = ["Google", "SignInWithApple"]

  access_token_validity = 1
  id_token_validity     = 1

  token_validity_units {
    access_token = "days"
    id_token     = "hours"
  }

  depends_on = [aws_cognito_identity_provider.apple]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = var.name
  user_pool_id = aws_cognito_user_pool.pool.id
}

resource "aws_cognito_identity_provider" "google" {
  user_pool_id  = aws_cognito_user_pool.pool.id
  provider_name = "Google"
  provider_type = "Google"

  attribute_mapping = {
    given_name  = "given_name"
    family_name = "family_name"
    email       = "email"
  }

  provider_details = {
    client_id        = var.google_client_id
    client_secret    = var.google_client_secret
    authorize_scopes = "openid email profile"
  }

  idp_identifiers = ["accounts.google.com"]
}

resource "aws_cognito_identity_provider" "apple" {
  user_pool_id  = aws_cognito_user_pool.pool.id
  provider_name = "SignInWithApple"
  provider_type = "SignInWithApple"

  attribute_mapping = {
    email       = "email"
    name        = "name"
    given_name  = "given_name"
    family_name = "family_name"
  }

  provider_details = {
    client_id        = var.apple_client_id
    team_id          = var.apple_team_id
    key_id           = var.apple_key_id
    private_key      = replace(var.apple_private_key, "\\n", "\n")
    authorize_scopes = "email name"
  }

  idp_identifiers = ["appleid.apple.com"]
}
