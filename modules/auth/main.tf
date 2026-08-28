data "aws_secretsmanager_secret" "oauth_secrets" {
  name = "${var.name}/auth-oauth-secrets"
}

data "aws_secretsmanager_secret_version" "oauth_secrets" {
  secret_id = data.aws_secretsmanager_secret.oauth_secrets.id
}

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

# Mobile app client. Present in state and in AWS but missing from configuration,
# so `terraform plan` wanted to destroy it — which would have invalidated client
# id 47mhivl8hddp07npmahgrgbs4q and broken sign-in for the mobile app.
#
# Transcribed from the live client (describe-user-pool-client) so this is a
# no-op reconciliation, not a change. Distinct from `client` above: it uses
# custom-scheme redirects for the native app rather than https URLs, no implicit
# flow, and no aws.cognito.signin.user.admin scope.
resource "aws_cognito_user_pool_client" "mobile_client" {
  name                = "${var.name}-mobile"
  user_pool_id        = aws_cognito_user_pool.pool.id
  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]

  callback_urls = ["upfrontbeats://auth-callback"]
  logout_urls   = ["upfrontbeats://sign-out"]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  supported_identity_providers = ["Google", "SignInWithApple"]

  # No client secret: a public native client cannot keep one.
  generate_secret = false

  refresh_token_validity        = 30
  access_token_validity         = 1
  id_token_validity             = 1
  auth_session_validity         = 3
  enable_token_revocation       = true
  prevent_user_existence_errors = "ENABLED"

  token_validity_units {
    access_token  = "days"
    id_token      = "hours"
    refresh_token = "days"
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

    # Maps the Google `sub` claim to the Cognito username. Configured on the
    # live provider but previously missing here, so an apply would have removed
    # it — changing how federated identities resolve to users and breaking
    # sign-in for existing accounts.
    username = "sub"
  }

  provider_details = {
    client_id        = var.google_client_id
    client_secret    = jsondecode(data.aws_secretsmanager_secret_version.oauth_secrets.secret_string)["google_client_secret"]
    authorize_scopes = "openid email profile"
  }

  idp_identifiers = ["accounts.google.com"]

  lifecycle {
    # Cognito populates the OIDC endpoints itself for the managed Google
    # provider type and returns them in provider_details. They are not in this
    # config, so Terraform reads them as removals on every plan. Ignoring them
    # keeps whatever Cognito set rather than trying to null out the endpoints
    # the provider needs to function.
    ignore_changes = [
      provider_details["attributes_url"],
      provider_details["attributes_url_add_attributes"],
      provider_details["authorize_url"],
      provider_details["oidc_issuer"],
      provider_details["token_request_method"],
      provider_details["token_url"],
    ]
  }
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

    # See the Google provider above: live configuration this file was missing.
    username = "sub"
  }

  provider_details = {
    client_id = var.apple_client_id
    team_id   = var.apple_team_id
    key_id    = var.apple_key_id
    private_key = replace(
      jsondecode(data.aws_secretsmanager_secret_version.oauth_secrets.secret_string)["apple_private_key"],
      "\\n", "\n"
    )
    authorize_scopes = "email name"
  }

  idp_identifiers = ["appleid.apple.com"]

  lifecycle {
    # As above: endpoints Cognito fills in for the managed SignInWithApple
    # provider type.
    ignore_changes = [
      provider_details["attributes_url_add_attributes"],
      provider_details["authorize_url"],
      provider_details["oidc_issuer"],
      provider_details["token_request_method"],
      provider_details["token_url"],
    ]
  }
}
