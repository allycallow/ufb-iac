# Wraps per-track AES content keys for offline downloads (see
# ufb-audio-processing's encrypt_download_asset/wrap_content_key). The
# audio-processing task encrypts with this key, the backend decrypts to hand
# the raw key to an authorized native client via GetDownloadAccess.
#
# Deliberately NOT scoped to either task role via this key's own policy (unlike
# modules/ddex-delivery/security.tf's CMK) - audio-processing and backend each
# need the *other* module to exist before their own module block could
# reference it, which would make the two modules depend on each other and
# Terraform would reject the plan as a cycle. Instead this key's policy only
# grants the account root, and each module grants itself kms:Encrypt /
# kms:Decrypt via its own tasks_iam_role_statements, taking this key's ARN as
# a plain one-directional input - the same pattern those modules already use
# for their other scoped permissions.
resource "aws_kms_key" "download_content_keys" {
  description             = "Wraps per-track AES content keys for offline download assets"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableIAMUserPermissions"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "download_content_keys" {
  name          = "alias/${local.name}-download-content-keys"
  target_key_id = aws_kms_key.download_content_keys.key_id
}
