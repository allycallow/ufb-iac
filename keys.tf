resource "tls_private_key" "media" {
  algorithm = "RSA"
}

# Signs cookies for the auth-only preview tier — kept separate from the
# full-track/paid key so a preview cookie can never satisfy the trusted
# key group on the full-track behavior, regardless of Resource scoping.
resource "tls_private_key" "preview_media" {
  algorithm = "RSA"
}

# Signs download-tier CDN URLs. Kept separate from the other two tiers for the
# same reason - but note this key only gates who can fetch the ciphertext
# object at all; the real access control for offline downloads is the
# separately-issued AES decryption key (see GetDownloadAccess / kms.tf), not
# this CloudFront signature.
resource "tls_private_key" "download_media" {
  algorithm = "RSA"
}
