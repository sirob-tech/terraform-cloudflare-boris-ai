# B.O.R.I.S Cloudflare onboarding Terraform module

Terraform you run against your own Cloudflare account to give B.O.R.I.S
read-only access to it: one account-owned API token, restricted to the
B.O.R.I.S egress IPs, holding only read permissions that carry no secrets and
no customer data.

You apply it with your own Cloudflare credential. After `apply`, the token is
registered with B.O.R.I.S, either inside `apply` or by one command you run.

Cloudflare has no workload identity federation for its API, so unlike the
B.O.R.I.S onboarding for AWS and GCP this module does create a long-lived
bearer credential. Most of this README is about how that credential is bounded.

> **Before you start**, get two things from the B.O.R.I.S team: the **egress
> IPs** of your B.O.R.I.S deployment, and a **connection secret** for this
> Cloudflare account. See [The connection secret](#the-connection-secret).

Not using Terraform? [`docs/dashboard-token.md`](docs/dashboard-token.md)
builds the same token in the Cloudflare dashboard and registers it with one
`curl`.

## What it creates

One **account-owned API token** (`cfat_…`) in the account you name, with:

- **Two allow policies**: one on the account, one on every zone in it. Zones
  added later are covered without a re-apply.
- **Read permission groups only**, chosen by
  [`classification.yaml`](classification.yaml) and resolved by name against
  Cloudflare's live permission catalogue at plan time. The
  `granted_permission_groups` output lists what the token holds.
- **A client IP restriction** (`allowed_ips`): Cloudflare refuses the token
  from any other address.
- **No expiry.** See [Rotation](#rotation).

Nothing else: no zone, DNS, Worker or Access setting is created or changed.

The token is owned by the account, not by a person, so it keeps working after
the member who applied the module leaves.

## What the token can read

Configuration and metadata across the account and its zones: DNS records, zone
settings, rulesets and WAF, load balancers, SSL, Access applications and
policies, Tunnels, Workers routes and metadata, Pages project metadata, Magic
and network configuration, analytics and billing. The full list is `allow` in
[`classification.yaml`](classification.yaml).

### What it deliberately cannot read

Some of Cloudflare's read groups return secrets or your users' data rather
than configuration. They are classified and left out:

- **Secret-bearing**: Secrets Store, Access service tokens, API tokens,
  Snippet source code, Workers Tail and Workers CI (both return script
  content), Turnstile secret keys, notification webhooks (their URLs embed
  credentials), and Zero Trust user, PII and audit-log data.
- **Data-bearing**: Workers KV, R2, D1, Queues, Vectorize, Images, Stream,
  Logs, AI Gateway (its logs hold prompts and responses), email security,
  packet captures, and Pages, whose read includes deployed content. B.O.R.I.S
  gets Pages Metadata Read instead.

The exact lists, with reasons, are `exclude_secret` and `exclude_data` in
`classification.yaml`. Write groups are never granted.

**Workers Scripts Read is the one exception.** It is granted although it can
also return Worker source code, because Cloudflare has no narrower group for
listing Workers and their bindings. Bindings come back with their names,
targets and plain-text values; `secret_text` values are never returned. To
keep the token out of script source, name the group in
`excluded_permission_groups`.

### New permissions are not granted until classified

A group is granted only when it is on the `allow` list. A read group Cloudflare
adds later, or one this module version does not know, is **not granted**: the
token fails closed and covers less until a module release classifies the group
and you apply it. The `unclassified_permission_groups` output lists such groups
in your account.

To withhold an allowed group too, name it in `excluded_permission_groups`.
B.O.R.I.S features that read it degrade accordingly.

### Products account tokens cannot reach

Cloudflare does not accept account-owned tokens for some products yet, so
B.O.R.I.S cannot see them however the token is scoped: **Page Rules,
Registrar, Turnstile, Super Bot Fight Mode, Intel Data Platform and the Zero
Trust Client Platform** (Cloudflare's
[compatibility matrix](https://developers.cloudflare.com/fundamentals/api/get-started/account-owned-tokens/#compatibility-matrix)).

## Usage

```hcl
module "boris_cloudflare" {
  source  = "sirob-tech/boris-ai/cloudflare"
  version = "~> 0.1"

  account_id  = "0123456789abcdef0123456789abcdef"
  allowed_ips = ["203.0.113.10", "203.0.113.11"] # from the B.O.R.I.S team

  enable_self_registration = true
  connection_secret        = var.connection_secret # TF_VAR_connection_secret
}
```

Runnable configurations are in [`examples/`](examples): `basic`
(self-registration) and `manual-registration`.

### The credential you apply with

Creating the token needs a Cloudflare credential that can create account API
tokens, such as an API token with **Account API Tokens: Edit**; in the
dashboard that takes **Super Administrator** or **API Token Provisioning**.
Cloudflare lets a member grant an account token only permissions they hold
themselves, so the credential also needs read access to everything on the
`allow` list.

That credential is more privileged than the token it creates. Teams that
manage Cloudflare in Terraform usually hold one already. It stays with you;
B.O.R.I.S never receives it.

### The token is in your Terraform state

Cloudflare returns a token's value once, at creation, and the provider keeps it
in state, marked sensitive. Anyone who can read your state can read the token.
The IP restriction limits where it can be used from, but treat your state
backend as holding a credential to your Cloudflare configuration.

No output carries the token value.

### `allowed_ips`

The egress IPs of your B.O.R.I.S deployment, as IPs or CIDRs. Required, and
neither an empty list nor a `/0` is accepted. Cloudflare rejects a bare address
in a token's IP condition (error 1001), so the module sends one as a `/32`
(IPv4) or `/128` (IPv6). If the IPs change, update the list and apply: the
token is updated in place and stays registered. Until you do, B.O.R.I.S calls
from the new IPs are refused.

## Registration

### Self-registration

With `enable_self_registration = true`, `apply` sends the token to
`PUT https://install.getboris.ai/cloudflare/install/<account_id>` after
creating it, and again whenever the token is replaced or `account_name` changes.
An unchanged re-apply sends nothing.

The token reaches `curl` through the environment and standard input, never its
command line.

Anything that is not a 2xx or a 4xx (a 5xx, a redirect, a network failure) is
retried for about four minutes; a fully stalled endpoint holds `apply` for up
to about eleven. Any 4xx fails `apply` at once, since none clears by retrying:
a `401` means the secret was not accepted, a `409` that it is already bound to
a different account. Terraform hides the command's output while it runs,
because its environment is sensitive, and prints it in the error if
registration fails. The token exists by then; the next `apply` retries the
registration.

`account_name` is sent with the token so B.O.R.I.S can label the account. It
defaults to the name Cloudflare reports.

### Manual registration

With self-registration off (the default), `apply` contacts only Cloudflare.
Register afterwards from the same Terraform root:

```sh
export BORIS_CONNECTION_SECRET='boris_...'
eval "$(terraform output -raw registration_command)"
```

The command reads the token from state with `terraform show -json` and pipes
it to `curl`, so it needs `jq` and read access to state. That output holds
the token's id, never its value.

### The connection secret

Issued by the B.O.R.I.S team, one per Cloudflare account, shaped
`boris_<16 chars>_<52 chars>`. It authenticates registration, and B.O.R.I.S
identifies you by it.

- **It binds to the first account it registers.** Keep it: a replaced token is
  registered again with the same secret.
- **A new secret is not sent on its own.** The module keeps no trace of the
  secret, so it cannot see it change. When the B.O.R.I.S team issues a new one,
  apply with
  `-replace='module.boris_cloudflare.terraform_data.register[0]'`.
- **Keep it out of state.** Pass it as `TF_VAR_connection_secret`, not in a
  committed `.tfvars`. The module keeps it out of state; a saved plan file
  (`terraform plan -out=…`) does not, so treat plan files as secret.

### Several accounts

One module instance covers one Cloudflare account. For several, use one
instance per account, each with its own connection secret.

## Rotation

The token does not expire. To rotate it:

```sh
terraform apply -replace='module.boris_cloudflare.cloudflare_account_token.boris'
```

Terraform creates the new token, registers it if self-registration is on (run
`registration_command` otherwise), then deletes the old one.

## Offboarding

`terraform destroy` deletes the token, which ends B.O.R.I.S's access at once.

Deleting or disabling the token in the dashboard (**Manage Account > Account
API Tokens**) also ends access, but only until the next `apply`: the provider
then creates a new token, and with self-registration on, registers it. Remove
the module too.

There is no deregistration call. Ask the B.O.R.I.S team to remove the account
from your deployment, so it stops trying to read it.

## The classification

[`classification.yaml`](classification.yaml) sorts Cloudflare's account- and
zone-scoped permission groups into `allow`, `exclude_secret`, `exclude_data`
and `write` (write groups whose names lack a write suffix such as `Edit`). It
is the single source for the module and for
[`docs/dashboard-token.md`](docs/dashboard-token.md), which
`scripts/classification.py render` generates and CI keeps in step.

A scheduled workflow compares the file with Cloudflare's live catalogue and
opens an issue listing the groups it does not cover.

## Versioning and upgrades

The version you pin decides which permission groups your token holds. Pin it,
and read the plan before applying an upgrade: a release that allows more
groups shows as an in-place change to the token's `policies`, and nothing
changes until you apply it.

## License

[Apache License 2.0](LICENSE). Apache-2.0 §6 grants no trademark rights: forks
are welcome, but must not be distributed under the B.O.R.I.S name.
