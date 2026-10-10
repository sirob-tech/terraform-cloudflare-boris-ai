# ---------------------------------------------------------------------------
# The account and the token
# ---------------------------------------------------------------------------

variable "account_id" {
  type        = string
  description = "ID of the Cloudflare account B.O.R.I.S may read (32 hex characters, shown on the account's overview page). One module instance covers one account."

  # Also keeps shell metacharacters out of the registration command, which
  # puts this value in the URL.
  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a Cloudflare account ID: 32 lowercase hex characters."
  }
}

variable "allowed_ips" {
  type        = list(string)
  description = "The B.O.R.I.S egress IPs for your deployment, supplied by the B.O.R.I.S team during onboarding, as IPs or CIDRs. The token is refused from any other address."

  # No default: an empty pin would leave the token usable from anywhere.
  validation {
    condition     = length(var.allowed_ips) > 0
    error_message = "allowed_ips must list at least one IP or CIDR. Ask the B.O.R.I.S team for your deployment's egress IPs."
  }

  # A bare address is checked as a /32 or /128. A /0 is refused for the same
  # reason as an empty list.
  validation {
    condition = alltrue([
      for ip in var.allowed_ips : can(cidrhost(
        strcontains(ip, "/") ? ip : (strcontains(ip, ":") ? "${ip}/128" : "${ip}/32"), 0
      )) && !endswith(ip, "/0")
    ])
    error_message = "allowed_ips entries must each be an IPv4 or IPv6 address or CIDR, e.g. \"203.0.113.10\" or \"2001:db8::/48\", with no surrounding whitespace. A /0 range is not accepted."
  }
}

variable "token_name" {
  type        = string
  description = "Name of the token as it appears in the Cloudflare dashboard."
  default     = "B.O.R.I.S read-only"

  validation {
    condition     = length(trimspace(var.token_name)) > 0 && length(var.token_name) <= 120
    error_message = "token_name must be 1-120 characters."
  }
}

variable "excluded_permission_groups" {
  type        = list(string)
  description = "Permission-group names to withhold on top of the shipped exclusions, e.g. [\"Billing Read\"]. Matching ignores case. Narrowing the token may degrade B.O.R.I.S features that depend on the withheld groups."
  default     = []
}

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

variable "account_name" {
  type        = string
  description = "Account name sent at registration. Leave empty to use the name Cloudflare reports for account_id."
  default     = ""
}

variable "enable_self_registration" {
  type        = bool
  description = "When true, the module registers the token with B.O.R.I.S inside apply (a PUT on create and whenever the token is replaced). When false (default), run the registration_command output after apply."
  default     = false
}

variable "registration_endpoint" {
  type        = string
  description = "Base URL of the B.O.R.I.S registration endpoint. Leave at the default unless the B.O.R.I.S team gives you another."
  default     = "https://install.getboris.ai"

  # Spliced into the registration command, so only URL characters pass.
  validation {
    condition     = can(regex("^https://[A-Za-z0-9.:/_-]+$", var.registration_endpoint))
    error_message = "registration_endpoint must be an https:// URL containing only letters, digits, and . : / _ -"
  }
}

variable "connection_secret" {
  type        = string
  description = "Per-connection secret issued by the B.O.R.I.S team, sent as an Authorization: Bearer credential. Required when enable_self_registration is true. Supply it as TF_VAR_connection_secret, not in a committed .tfvars."
  default     = ""
  sensitive   = true

  validation {
    condition     = !var.enable_self_registration || length(var.connection_secret) > 0
    error_message = "connection_secret is required when enable_self_registration is true. Ask the B.O.R.I.S team to issue one for this Cloudflare account."
  }

  # Catches a truncated paste at plan time rather than as a 401 mid-apply.
  validation {
    condition     = var.connection_secret == "" || can(regex("^boris_[a-z2-7]{16}_[a-z2-7]{52}$", var.connection_secret))
    error_message = "connection_secret must look like boris_<16 chars>_<52 chars>, using only lowercase letters and the digits 2-7. Check for a truncated copy-paste."
  }
}
