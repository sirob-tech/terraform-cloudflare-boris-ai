# Creates the token without contacting B.O.R.I.S. Afterwards, with
# BORIS_CONNECTION_SECRET exported, register it from this directory:
#   eval "$(terraform output -raw registration_command)"

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.13.0, < 6.0.0"
    }
  }
}

provider "cloudflare" {}

module "boris_cloudflare" {
  # Published as:
  #   source  = "sirob-tech/boris-ai/cloudflare"
  #   version = "~> 0.1"
  source = "../../"

  account_id  = "0123456789abcdef0123456789abcdef"
  allowed_ips = ["203.0.113.10", "2001:db8:10::/48"]

  # Withhold a group B.O.R.I.S would otherwise read.
  excluded_permission_groups = ["Billing Read"]
}

output "registration_command" {
  description = "Run after apply to register the token. Requires BORIS_CONNECTION_SECRET in your shell, jq, and read access to this root's state."
  value       = module.boris_cloudflare.registration_command
}
