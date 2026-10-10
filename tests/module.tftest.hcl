# The root module against a mock provider: no Cloudflare credentials, no
# network. Every run is a plan except the one that checks output contents.

mock_provider "cloudflare" {
  override_data {
    target = data.cloudflare_account.this
    values = { name = "Example Account" }
  }
}

# Mocked data sources cannot return a multi-element nested list, so the
# selection is tested on its own (permission_policies.tftest.hcl) and stubbed here.
override_module {
  target = module.permission_policies
  outputs = {
    granted      = ["DNS Read", "Zone Read"]
    unclassified = ["Brand New Read"]
    policies = [{
      effect            = "allow"
      permission_groups = [{ id = "z-dns" }, { id = "z-zone" }]
      resources         = "{\"com.cloudflare.api.account.0123456789abcdef0123456789abcdef\":{\"com.cloudflare.api.account.zone.*\":\"*\"}}"
    }]
  }
}

variables {
  account_id  = "0123456789abcdef0123456789abcdef"
  allowed_ips = ["203.0.113.10", "2001:db8::/48"]
}

run "token_is_wired_to_the_selection" {
  command = plan

  assert {
    condition     = toset(flatten([for p in cloudflare_account_token.boris.policies : [for g in p.permission_groups : g.id]])) == toset(["z-dns", "z-zone"])
    error_message = "The token must carry the selected policies."
  }

  assert {
    condition     = output.granted_permission_groups == ["DNS Read", "Zone Read"] && output.unclassified_permission_groups == ["Brand New Read"]
    error_message = "The outputs must report the selection."
  }

  assert {
    condition     = cloudflare_account_token.boris.condition.request_ip.in == tolist(["203.0.113.10/32", "2001:db8::/48"])
    error_message = "The token must be pinned to allowed_ips, a bare address sent as a /32 (Cloudflare refuses bare IPs)."
  }

  assert {
    condition     = cloudflare_account_token.boris.expires_on == null
    error_message = "The token must not expire."
  }
}

run "fails_when_nothing_would_be_granted" {
  command = plan

  override_module {
    target = module.permission_policies
    outputs = {
      granted      = []
      unclassified = ["Brand New Read"]
      policies     = []
    }
  }

  expect_failures = [cloudflare_account_token.boris]
}

run "accepts_ips_and_cidrs" {
  command = plan

  variables {
    allowed_ips = ["203.0.113.10", "198.51.100.0/24", "2001:db8::1", "2001:db8::/48"]
  }

  assert {
    condition     = cloudflare_account_token.boris.condition.request_ip.in == tolist(["203.0.113.10/32", "198.51.100.0/24", "2001:db8::1/128", "2001:db8::/48"])
    error_message = "Bare addresses must go out as /32 or /128; CIDRs unchanged."
  }
}

run "rejects_empty_ip_list" {
  command = plan
  variables {
    allowed_ips = []
  }
  expect_failures = [var.allowed_ips]
}

run "rejects_ipv4_catch_all" {
  command = plan
  variables {
    allowed_ips = ["203.0.113.10", "0.0.0.0/0"]
  }
  expect_failures = [var.allowed_ips]
}

run "rejects_ipv6_catch_all" {
  command = plan
  variables {
    allowed_ips = ["::/0"]
  }
  expect_failures = [var.allowed_ips]
}

run "rejects_malformed_ip" {
  command = plan
  variables {
    allowed_ips = ["203.0.113.300"]
  }
  expect_failures = [var.allowed_ips]
}

run "rejects_padded_ip" {
  command = plan
  variables {
    allowed_ips = [" 203.0.113.10"]
  }
  expect_failures = [var.allowed_ips]
}

run "registration_off_by_default" {
  command = plan

  assert {
    condition     = length(terraform_data.register) == 0
    error_message = "Self-registration must be off unless enabled."
  }

  assert {
    condition     = output.registration_mode == "manual: run the registration_command output"
    error_message = "registration_mode must point at the manual command when self-registration is off."
  }
}

run "registration_on_when_enabled" {
  command = plan

  variables {
    enable_self_registration = true
    connection_secret        = "boris_abcdefghijklmnop_abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
  }

  assert {
    condition     = length(terraform_data.register) == 1
    error_message = "Self-registration must create the registration resource."
  }

  assert {
    condition     = startswith(output.registration_mode, "self-registration:")
    error_message = "registration_mode must report self-registration."
  }
  assert {
    condition     = terraform_data.register[0].triggers_replace.account_name == "Example Account"
    error_message = "Renaming the account must send the registration again."
  }
}

run "registration_requires_secret" {
  command = plan
  variables {
    enable_self_registration = true
  }
  expect_failures = [var.connection_secret]
}

run "rejects_truncated_secret" {
  command = plan
  variables {
    enable_self_registration = true
    connection_secret        = "boris_abcdefghijklmnop_abc"
  }
  expect_failures = [var.connection_secret]
}

run "no_token_value_in_outputs" {
  command = apply

  override_resource {
    target = cloudflare_account_token.boris
    values = {
      id    = "token-id-0001"
      value = "cfat_MOCKTOKENVALUEdoNotLeak"
    }
  }

  variables {
    account_name = "Acme's account"
  }

  assert {
    condition = !anytrue([for v in [
      output.account_id,
      output.token_id,
      jsonencode(output.granted_permission_groups),
      jsonencode(output.unclassified_permission_groups),
      output.registration_mode,
      output.registration_command,
    ] : strcontains(v, "cfat_MOCKTOKENVALUE")])
    error_message = "A non-sensitive output contains the token value."
  }

  assert {
    condition     = strcontains(output.registration_command, "--arg id 'token-id-0001'") && strcontains(output.registration_command, "--arg name 'Acme'\\''s account'")
    error_message = "registration_command must select the token by id and shell-quote the account name: ${output.registration_command}"
  }

  assert {
    condition     = strcontains(output.registration_command, "'https://install.getboris.ai/cloudflare/install/0123456789abcdef0123456789abcdef'")
    error_message = "registration_command must PUT to the default endpoint for this account."
  }

  assert {
    condition     = length(data.cloudflare_account.this) == 0
    error_message = "An explicit account_name must skip the account lookup."
  }
}
