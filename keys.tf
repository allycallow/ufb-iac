resource "tls_private_key" "media" {
  algorithm = "RSA"
}

# Signs cookies for the auth-only preview tier — kept separate from the
# full-track/paid key so a preview cookie can never satisfy the trusted
# key group on the full-track behavior, regardless of Resource scoping.
resource "tls_private_key" "preview_media" {
  algorithm = "RSA"
}
