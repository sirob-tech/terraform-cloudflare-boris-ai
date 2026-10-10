output "account_id" {
  description = "Cloudflare account the token reads."
  value       = var.account_id
}

output "token_id" {
  description = "ID of the B.O.R.I.S token, as shown in the dashboard under Manage Account > Account API Tokens. Not the token value, which no output carries."
  value       = cloudflare_account_token.boris.id
}

output "granted_permission_groups" {
  description = "Names of the permission groups the token holds."
  value       = module.permission_policies.granted
}

output "unclassified_permission_groups" {
  description = "Read permission groups in Cloudflare's catalogue that this module version has not classified, and therefore did not grant."
  value       = module.permission_policies.unclassified
}

# The mode, not the outcome: a provisioner's result cannot reach an output, and a
# failed registration still writes outputs to state.
output "registration_mode" {
  description = "How the token is registered with B.O.R.I.S: by apply itself, or by running registration_command."
  value       = var.enable_self_registration ? "self-registration: apply registers the token and fails if registration fails" : "manual: run the registration_command output"
}

# The token value is read from state at run time (terraform show -json), so
# it is never in an output, on a command line, or in this string.
output "registration_command" {
  description = "Manual registration command for when enable_self_registration is false. Run it from this Terraform root with BORIS_CONNECTION_SECRET exported; it needs jq and read access to state."
  value = format(
    "terraform show -json | jq -c --arg id '%s' --arg name '%s' '(first(.values.root_module | .. | objects | select(.type? == \"cloudflare_account_token\" and .values.id? == $id) | .values.value) // error(\"token not found in state\")) | {token: ., account_name: $name}' | curl -sS --fail-with-body -X PUT '%s' -H 'Content-Type: application/json' -H \"Authorization: Bearer $BORIS_CONNECTION_SECRET\" --data-binary @-",
    cloudflare_account_token.boris.id,
    replace(local.account_name, "'", "'\\''"),
    local.registration_url,
  )
}
