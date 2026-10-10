<!-- Generated from classification.yaml by scripts/classification.py render. Do not edit. -->
# Creating the B.O.R.I.S token in the Cloudflare dashboard

For accounts not managed with Terraform. This builds the same token the module
creates: account-owned, read-only, pinned to the B.O.R.I.S egress IPs, no
expiry. Before you start, get two things from the B.O.R.I.S team: your egress
IPs and a connection secret for this account.

## 1. Create the token

In the Cloudflare dashboard, open the account, then **Manage Account > Account
API Tokens > Create Token > Create Custom Token**.

- **Token name:** `B.O.R.I.S read-only`.
- **Permissions:** add every permission in the list below at **Read**. Each
  appears under **Account** or **Zone** in the first drop-down; a few appear
  under both, and then it goes under both.
- **Account Resources:** Include, this account.
- **Zone Resources:** Include, All zones from an account, this account. This
  also covers zones added later.
- **Client IP Address Filtering:** Is in, each egress IP the B.O.R.I.S team
  gave you, written as a CIDR: `203.0.113.10/32` for a single address.
- **TTL:** leave empty, so the token does not expire.

Create it and copy the token: Cloudflare shows it once.

### Permissions to grant

- #reports:read
- Access: Apps and Policies Read
- Access: Apps Read
- Access: Custom Pages Read
- Access: Device Posture Read
- Access: Groups Read
- Access: Identity Providers Read
- Access: Keys Read
- Access: Mutual TLS Certificates Read
- Access: Organizations Read
- Access: Organizations, Identity Providers, and Groups Read
- Access: Policies Read
- Access: SSH Auditing Read
- Access: Tags Read
- Account Analytics Read
- Account API Gateway Read
- Account Custom Pages Read
- Account DNS Settings Read
- Account Filter Lists Read
- Account Firewall Access Rules Read
- Account Read
- Account Rule Lists Read
- Account Rulesets Read
- Account Security Center Insights
- Account Settings Read
- Account WAF Read
- Account Waiting Rooms Read
- Account: SSL and Certificates Read
- Address Maps Read
- Allow Request Tracer Read
- Analytics Read
- API Gateway Read
- Billing Read
- Bot Management Read
- Browser Rendering Read
- Bulk URL Redirects Read
- Cache Rules Read
- Cache Settings Read
- Calls Read
- China Network Steering Read
- Client-side security Read
- Cloud Connector Read
- Cloudchamber Read
- Cloudflare One Connector: cloudflared Read
- Cloudflare One Connector: WARP Read
- Cloudflare One Connectors Read
- Cloudflare One Networks Read
- Cloudflare Realtime Read
- Cloudflare Tunnel Read
- Config Rules Read
- Config Settings Read
- Constellation Read
- Containers Read
- Custom Error Rules Read
- Custom Errors Read
- Custom Pages Read
- DDoS Protection Read
- DNS Firewall Read
- DNS Read
- DNS View Read
- Domain API Gateway Read
- Domain Page Shield Read
- Dynamic URL Redirects Read
- Email Routing Addresses Read
- Email Routing Rules Read
- Firewall Services Read
- Flagship Read
- Fraud Detection Read
- Health Checks Read
- HTTP DDoS Managed Ruleset Read
- Hyperdrive Read
- Intel Read
- IOT Read
- IP Prefixes: BGP On Demand Read
- IP Prefixes: Read
- L3/4 DDoS Managed Ruleset Read
- L4 DDoS Managed Ruleset Read
- Load Balancers Account Read
- Load Balancers Read
- Load Balancing: Monitors and Pools Read
- Magic Firewall Read
- Magic Network Monitoring Config Read
- Magic Network Monitoring Read
- Magic Transit Read
- Magic WAN Read
- Managed headers Read
- Mass URL Redirects Read
- MCP Portals Read
- OAuth Client Read
- Origin Read
- Origin Rules Read
- Page Rules Read
- Page Shield Read
- Pages Metadata Read
- Pipelines Read
- Realtime Read
- Response Compression Read
- Rule Policies Read
- Sanitize Read
- Select Configuration Read
- Single Redirect Read
- SSL and Certificates Read
- SSO Connector Read
- Transform Rules Read
- Waiting Room Read
- Waiting Rooms Read
- Web3 Hostnames Read
- Workers AI Read
- Workers Containers Read
- Workers Pipelines Read
- Workers Routes Read
- Workers Scripts Read
- Zaraz Read
- Zero Trust Read
- Zero Trust Resilience Read
- Zone DNS Settings Read
- Zone Read
- Zone Security Center Insights
- Zone Settings Read
- Zone Transform Rules Read
- Zone Versioning Read
- Zone WAF Read
- Zone Zone Read

### Permissions to leave out

Every other read permission. Unless the B.O.R.I.S team publishes an updated
list, a permission that is not above stays out, including any Cloudflare adds
later. These are left out on purpose:

**Secret-bearing** — credentials, secret values, code, or Zero Trust user and
log data:

- Access: Audit Logs Read
- Access: Policy Test Read
- Access: Population Read
- Access: SCIM Logs Read
- Access: Service Tokens Read
- Access: Users Read
- Account API Tokens Read
- Cloudflare DEX Read
- Notifications Read — webhook destinations are URLs with embedded secrets
- Secrets Store Read
- Snippets Read — customer code, like Worker content
- Turnstile Read — widget reads return the secret key
- Turnstile Sites Read
- Workers CI Read — legacy alias that reads Worker script content
- Workers Tail Read — also grants reading Worker script content
- Zero Trust Report
- Zero Trust: PII Read

**Data-bearing** — stored objects, content, logs and traffic records:

- AI Gateway Read — gateway logs hold prompts and responses
- Artifacts Read
- Auto Rag Read
- Bot Management Feedback Read
- Bot Management Feedback Report Read
- Cloud Email Security: Read
- Cloudflare CASB Read
- Cloudflare Images Read
- Cloudflare Pages Read — same as Pages Read: project metadata plus deployed content
- Cloudforce One Read
- D1 Read
- DDoS Botnet Feed Read
- Dmarc Management Read
- Email Security DMARC Reports Read
- Email Security Read
- Flagship Evaluate
- Images Read
- Logs Read
- Magic Firewall Packet Captures - Read PCAPs API
- Magic Firewall Packet Captures Read
- Pages Read
- Queues Read
- Stream Read
- Trust and Safety Read
- URL Scanner Read
- Vectorize Read
- Workers KV Storage Read
- Workers Observability Read — legacy, Workers logs and traces
- Workers R2 Data Catalog Read
- Workers R2 Storage Read

## 2. Register it

Run this in a shell, replacing `<account_id>` (32 hex characters, on the
account's overview page) and the account name. The token is read from the
prompt and passed to `curl` on standard input, so it does not appear in your
shell history or the process list. An account name containing `"` or `\`
must be escaped for JSON.

```sh
export BORIS_CONNECTION_SECRET='boris_...'
printf 'Cloudflare token: '; read -rs CLOUDFLARE_TOKEN; echo
printf '{"token":"%s","account_name":"%s"}' "$CLOUDFLARE_TOKEN" 'Your account name' |
  curl -sS --fail-with-body -X PUT \
    'https://install.getboris.ai/cloudflare/install/<account_id>' \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer $BORIS_CONNECTION_SECRET" \
    --data-binary @-
unset CLOUDFLARE_TOKEN
```

A `2xx` means B.O.R.I.S accepted the token. A `401` means the connection secret
was not accepted, and a `409` that it is already bound to a different account;
neither clears by retrying, so contact the B.O.R.I.S team.

To revoke access, delete the token under **Account API Tokens**.
