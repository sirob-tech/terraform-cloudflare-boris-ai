locals {
  account_name     = var.account_name != "" ? var.account_name : one(data.cloudflare_account.this[*].name)
  registration_url = "${trimsuffix(var.registration_endpoint, "/")}/cloudflare/install/${var.account_id}"

  # Cloudflare's request_ip condition takes CIDRs only and rejects a bare address
  # (error 1001 "invalid CIDR"), so bare entries go out as /32 or /128.
  allowed_cidrs = [for ip in var.allowed_ips : strcontains(ip, "/") ? ip : (strcontains(ip, ":") ? "${ip}/128" : "${ip}/32")]
}
