# The token's permission selection, run against the shipped classification and
# a fixed catalogue. No provider involved.

variables {
  account_id     = "0123456789abcdef0123456789abcdef"
  classification = yamldecode(file("classification.yaml"))
  catalogue = [
    { id = "a-settings", name = "Account Settings Read", scopes = ["com.cloudflare.api.account"] },
    { id = "a-billing", name = "Billing Read", scopes = ["com.cloudflare.api.account"] },
    { id = "a-access", name = "Access: Apps and Policies Read", scopes = ["com.cloudflare.api.account"] },
    { id = "z-access", name = "Access: Apps and Policies Read", scopes = ["com.cloudflare.api.account.zone"] },
    { id = "b-apigw", name = "API Gateway Read", scopes = ["com.cloudflare.api.account", "com.cloudflare.api.account.zone"] },
    { id = "z-dns", name = "DNS Read", scopes = ["com.cloudflare.api.account.zone"] },
    { id = "z-zone", name = "Zone Read", scopes = ["com.cloudflare.api.account.zone"] },
    { id = "z-headers", name = "managed HEADERS read", scopes = ["com.cloudflare.api.account.zone"] },
    { id = "a-secrets", name = "Secrets Store Read", scopes = ["com.cloudflare.api.account"] },
    { id = "a-svctok", name = "Access: Service Tokens Read", scopes = ["com.cloudflare.api.account"] },
    { id = "a-tokens", name = "Account API Tokens Read", scopes = ["com.cloudflare.api.account"] },
    { id = "a-kv", name = "Workers KV Storage Read", scopes = ["com.cloudflare.api.account"] },
    { id = "a-r2", name = "Workers R2 Storage Read", scopes = ["com.cloudflare.api.account"] },
    { id = "a-logs", name = "Logs Read", scopes = ["com.cloudflare.api.account"] },
    { id = "z-dns-w", name = "DNS Write", scopes = ["com.cloudflare.api.account.zone"] },
    { id = "z-shield", name = "Page Shield", scopes = ["com.cloudflare.api.account.zone"] },
    { id = "a-new", name = "Brand New Read", scopes = ["com.cloudflare.api.account"] },
    { id = "u-user", name = "User Details Read", scopes = ["com.cloudflare.api.user"] },
    { id = "r-bucket", name = "Unlisted Bucket Read", scopes = ["com.cloudflare.edge.r2.bucket"] },
  ]
}

run "grants_only_allowed_groups" {
  command = plan

  module {
    source = "./modules/permission-policies"
  }

  assert {
    condition = output.granted == tolist([
      "API Gateway Read",
      "Access: Apps and Policies Read",
      "Account Settings Read",
      "Billing Read",
      "DNS Read",
      "Zone Read",
      "managed HEADERS read",
    ])
    error_message = "Granted groups are not exactly the allowed groups in the catalogue: ${jsonencode(output.granted)}"
  }

  assert {
    condition = [for p in output.policies : [for g in p.permission_groups : g.id]] == [
      ["a-access", "a-billing", "a-settings", "b-apigw"],
      ["b-apigw", "z-access", "z-dns", "z-headers", "z-zone"],
    ]
    error_message = "Account and zone policies do not hold the expected group ids: ${jsonencode(output.policies)}"
  }

  assert {
    condition = [for p in output.policies : jsondecode(p.resources)] == [
      { "com.cloudflare.api.account.0123456789abcdef0123456789abcdef" = "*" },
      { "com.cloudflare.api.account.0123456789abcdef0123456789abcdef" = { "com.cloudflare.api.account.zone.*" = "*" } },
    ]
    error_message = "Policies must cover the account and all of its zones, and nothing else."
  }

  assert {
    condition     = alltrue([for p in output.policies : p.effect == "allow"])
    error_message = "Every policy must be an allow policy."
  }
}

run "never_grants_secret_data_write_or_unknown_groups" {
  command = plan

  module {
    source = "./modules/permission-policies"
  }

  assert {
    condition = length(setintersection(
      toset(flatten([for p in output.policies : [for g in p.permission_groups : g.id]])),
      toset(["a-secrets", "a-svctok", "a-tokens", "a-kv", "a-r2", "a-logs", "z-dns-w", "z-shield", "a-new", "u-user", "r-bucket"]),
    )) == 0
    error_message = "A secret-bearing, data-bearing, write, unknown or out-of-scope group was granted."
  }

  assert {
    condition     = output.unclassified == tolist(["Brand New Read"])
    error_message = "Unknown read groups must be reported, and write, user and bucket groups must not: ${jsonencode(output.unclassified)}"
  }
}

run "an_exclusion_wins_over_allow" {
  command = plan

  module {
    source = "./modules/permission-policies"
  }

  variables {
    classification = {
      allow          = ["DNS Read", "Secrets Store Read"]
      exclude_secret = ["Secrets Store Read"]
      exclude_data   = []
      write          = []
    }
  }

  assert {
    condition     = output.granted == tolist(["DNS Read"])
    error_message = "A group on both the allow list and an exclusion list must be withheld."
  }
}

run "customer_exclusions_are_withheld" {
  command = plan

  module {
    source = "./modules/permission-policies"
  }

  variables {
    excluded_permission_groups = [" billing read "]
  }

  assert {
    condition     = !contains(output.granted, "Billing Read") && length(output.policies[0].permission_groups) == 3
    error_message = "excluded_permission_groups must withhold an otherwise allowed group."
  }
}

run "omits_an_empty_policy" {
  command = plan

  module {
    source = "./modules/permission-policies"
  }

  variables {
    catalogue = [
      { id = "z-dns", name = "DNS Read", scopes = ["com.cloudflare.api.account.zone"] },
      { id = "a-kv", name = "Workers KV Storage Read", scopes = ["com.cloudflare.api.account"] },
    ]
  }

  assert {
    condition     = length(output.policies) == 1 && jsondecode(output.policies[0].resources) == { "com.cloudflare.api.account.0123456789abcdef0123456789abcdef" = { "com.cloudflare.api.account.zone.*" = "*" } }
    error_message = "With no account-scoped group granted, only the zone policy may be emitted."
  }
}

run "grants_nothing_from_an_unclassified_catalogue" {
  command = plan

  module {
    source = "./modules/permission-policies"
  }

  variables {
    catalogue = [
      { id = "a-new", name = "Brand New Read", scopes = ["com.cloudflare.api.account"] },
      { id = "a-secrets", name = "Secrets Store Read", scopes = ["com.cloudflare.api.account"] },
    ]
  }

  assert {
    condition     = length(output.policies) == 0 && length(output.granted) == 0
    error_message = "Unknown and excluded groups must never be granted."
  }
}
