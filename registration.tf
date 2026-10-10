# Optional self-registration, so onboarding completes in one apply. A
# create-time terraform_data + local-exec rather than the http data source,
# which would re-run on every plan.

locals {
  # Sensitive because it carries the token. It reaches curl only through the
  # environment and stdin, never the command line, state or a log.
  registration_body = jsonencode({
    token        = cloudflare_account_token.boris.value
    account_name = local.account_name
  })
}

resource "terraform_data" "register" {
  count = var.enable_self_registration ? 1 : 0

  # A new token or a new account name is worth sending again. The secret and the
  # token value stay out, as triggers are kept in state: a new secret is sent
  # with -replace (README, "The connection secret").
  triggers_replace = {
    account_id   = var.account_id
    token_id     = cloudflare_account_token.boris.id
    account_name = local.account_name
  }

  # Only registration_endpoint and account_id are interpolated, both validated
  # to shell-safe characters; the secret and the body arrive by environment.
  provisioner "local-exec" {
    environment = {
      BORIS_CONNECTION_SECRET = var.connection_secret
      BORIS_REGISTRATION_BODY = local.registration_body
    }

    # Retries 5xx, redirects and transport failures (curl's 000) for ~4 minutes;
    # every 4xx is terminal. Terraform hides this output while it runs, as the
    # environment is sensitive, and prints it in the error if the command fails.
    command = <<-EOT
      url='${local.registration_url}'
      for delay in 0 15 30 30 60 60 60; do
        if [ "$delay" -gt 0 ]; then sleep "$delay"; fi

        resp=$(printf '%s' "$BORIS_REGISTRATION_BODY" | curl -sS -w '\n%%{http_code}' --connect-timeout 10 --max-time 60 \
          -X PUT "$url" \
          -H 'Content-Type: application/json' \
          -H "Authorization: Bearer $BORIS_CONNECTION_SECRET" \
          --data-binary @-) || true
        code=$(printf '%s\n' "$resp" | tail -n 1)
        message=$(printf '%s\n' "$resp" | sed '$d')

        case "$code" in
          2??)
            exit 0
            ;;
          401)
            echo "B.O.R.I.S: registration was refused: the connection secret was not accepted." >&2
            echo "B.O.R.I.S: this does not clear by retrying. Ask the B.O.R.I.S team to re-issue it." >&2
            exit 1
            ;;
          409)
            echo "B.O.R.I.S: registration was refused: $message" >&2
            echo "B.O.R.I.S: this does not clear by retrying — contact the B.O.R.I.S team." >&2
            exit 1
            ;;
          4??)
            echo "B.O.R.I.S: registration was rejected (HTTP $code): $message" >&2
            echo "B.O.R.I.S: this does not clear by retrying. Check the module inputs, then contact the B.O.R.I.S team." >&2
            exit 1
            ;;
          *)
            echo "B.O.R.I.S: registration attempt failed (HTTP $${code:-no response}); retrying" >&2
            ;;
        esac
      done
      echo "B.O.R.I.S: registration failed after retries. Re-run 'terraform apply' to retry, or register by hand with the registration_command output." >&2
      exit 1
    EOT
  }
}
