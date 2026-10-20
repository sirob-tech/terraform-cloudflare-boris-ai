# One Cloudflare account, registered with B.O.R.I.S inside apply. Replace the
# placeholders; the egress IPs and the connection secret come from the
# B.O.R.I.S team.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.13.0, < 6.0.0"
    }
  }
}

# Reads CLOUDFLARE_API_TOKEN from the environment: a credential that can
# create account API tokens in this account.
provider "cloudflare" {}

variable "connection_secret" {
  type        = string
  description = "Per-connection secret issued by the B.O.R.I.S team. Supply it as TF_VAR_connection_secret rather than in a committed .tfvars."
  sensitive   = true
}

module "boris_cloudflare" {
  # Published as:
  #   source  = "sirob-tech/boris-ai/cloudflare"
  #   version = "~> 0.1"
  source = "../../"

  account_id  = "0123456789abcdef0123456789abcdef"
  allowed_ips = ["203.0.113.10", "203.0.113.11"]

  enable_self_registration = true
  connection_secret        = var.connection_secret
}

output "granted_permission_groups" {
  description = "Permission groups the token holds."
  value       = module.boris_cloudflare.granted_permission_groups
}

output "unclassified_permission_groups" {
  description = "Read groups this module version has not classified and did not grant."
  value       = module.boris_cloudflare.unclassified_permission_groups
}
