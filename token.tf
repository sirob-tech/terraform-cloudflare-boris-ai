# The live catalogue, so ids are never hard-coded. The default cap is 1000
# groups; raised so a growing catalogue is not silently cut short.
data "cloudflare_account_api_token_permission_groups_list" "catalogue" {
  account_id = var.account_id
  max_items  = 5000
}

module "permission_policies" {
  source = "./modules/permission-policies"

  account_id                 = var.account_id
  catalogue                  = data.cloudflare_account_api_token_permission_groups_list.catalogue.result
  classification             = yamldecode(file("${path.module}/classification.yaml"))
  excluded_permission_groups = var.excluded_permission_groups
}

data "cloudflare_account" "this" {
  count      = var.account_name == "" ? 1 : 0
  account_id = var.account_id
}

# Account-owned, so it survives the departure of whoever applied the module.
# No expiry; on -replace the new token exists before the old one is deleted.
resource "cloudflare_account_token" "boris" {
  account_id = var.account_id
  name       = var.token_name
  policies   = module.permission_policies.policies

  condition = {
    request_ip = {
      in = local.allowed_cidrs
    }
  }

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = length(module.permission_policies.policies) > 0
      error_message = "None of the allowed permission groups was found in this account's Cloudflare catalogue, so the token would grant nothing. Check that account_id is right and that the applying credential can read API token permission groups."
    }
  }
}
