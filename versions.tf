# 1.9 for cross-variable validation (connection_secret is required only when
# self-registration is on). 5.13 is where account-token policy `resources`
# became a JSON string, which token.tf relies on.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.13.0, < 6.0.0"
    }
  }
}
