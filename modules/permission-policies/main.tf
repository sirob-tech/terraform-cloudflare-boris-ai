# Turns Cloudflare's permission-group catalogue and the classification into
# token policies. Separate from the root so the selection can be tested
# against a fixed catalogue.

variable "account_id" {
  type        = string
  description = "Cloudflare account the policies cover."
}

variable "catalogue" {
  type = list(object({
    id     = string
    name   = string
    scopes = list(string)
  }))
  description = "Cloudflare's permission-group catalogue for the account."
}

variable "classification" {
  type = object({
    allow          = list(string)
    exclude_secret = list(string)
    exclude_data   = list(string)
    write          = list(string)
  })
  description = "The decoded classification.yaml."
}

variable "excluded_permission_groups" {
  type        = list(string)
  description = "Further group names to withhold."
  default     = []
}

locals {
  scope_account = "com.cloudflare.api.account"
  scope_zone    = "com.cloudflare.api.account.zone"

  # Names compare case- and whitespace-insensitively, as Cloudflare's own
  # catalogue has names differing only in case.
  allowed = toset([for n in var.classification.allow : lower(trimspace(n))])
  withheld = toset([for n in concat(
    var.classification.exclude_secret,
    var.classification.exclude_data,
    var.classification.write,
    var.excluded_permission_groups,
  ) : lower(trimspace(n))])
  classified = setunion(local.allowed, local.withheld)

  # Account tokens hold only account- and zone-scoped groups; user- and
  # bucket-scoped ones are dropped before anything is matched.
  catalogue = [
    for g in var.catalogue : g
    if contains(g.scopes, local.scope_account) || contains(g.scopes, local.scope_zone)
  ]

  # Fail closed: granted only when on the allow list and on no other list. A
  # group Cloudflare adds later is not granted until it is classified.
  granted = [
    for g in local.catalogue : g
    if contains(local.allowed, lower(trimspace(g.name))) && !contains(local.withheld, lower(trimspace(g.name)))
  ]

  account_resource = "${local.scope_account}.${var.account_id}"
}

output "granted" {
  description = "Names of the granted groups."
  value       = sort(distinct([for g in local.granted : g.name]))
}

output "unclassified" {
  description = "Account- and zone-scoped read groups the classification does not mention. Not granted."
  value = sort(distinct([
    for g in local.catalogue : g.name
    if !contains(local.classified, lower(trimspace(g.name))) && !can(regex("(?i)( edit| write| revoke| run| purge| admin|:edit)$", trimspace(g.name)))
  ]))
}

# One policy on the account, one on every zone in it, present and future. A
# group scoped to both lands in both; an empty policy is left out.
output "policies" {
  description = "Policies for cloudflare_account_token."
  value = [
    for p in [
      {
        ids       = sort(distinct([for g in local.granted : g.id if contains(g.scopes, local.scope_account)]))
        resources = jsonencode({ (local.account_resource) = "*" })
      },
      {
        ids       = sort(distinct([for g in local.granted : g.id if contains(g.scopes, local.scope_zone)]))
        resources = jsonencode({ (local.account_resource) = { "${local.scope_zone}.*" = "*" } })
      },
      ] : {
      effect            = "allow"
      permission_groups = [for id in p.ids : { id = id }]
      resources         = p.resources
    } if length(p.ids) > 0
  ]
}
