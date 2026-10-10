#!/usr/bin/env python3
"""Checks classification.yaml, renders docs/dashboard-token.md from it, and
diffs it against Cloudflare's live permission-group catalogue. Stdlib only."""

import argparse
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLASSIFICATION = ROOT / "classification.yaml"
DASHBOARD_DOC = ROOT / "docs" / "dashboard-token.md"
LISTS = ("allow", "exclude_secret", "exclude_data", "write")
WRITE_SUFFIXES = (" edit", " write", " revoke", " run", " purge", " admin", ":edit")
SCOPES = ("com.cloudflare.api.account", "com.cloudflare.api.account.zone")

# The file is kept to one shape: top-level list keys, then `- "name"  # reason`.
# Parsing it by line keeps the reasons and avoids a YAML dependency.
KEY_RE = re.compile(r"^([a-z_]+):\s*$")
ITEM_RE = re.compile(r'^  - "([^"]+)"\s*(?:#\s*(.*))?$')


def key(name):
    return name.strip().lower()


def load():
    lists = {k: [] for k in LISTS}
    current = None
    for n, line in enumerate(CLASSIFICATION.read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if m := KEY_RE.match(line):
            if m.group(1) not in lists:
                sys.exit(f"classification.yaml:{n}: unknown list {m.group(1)!r}")
            current = m.group(1)
        elif (m := ITEM_RE.match(line)) and current:
            lists[current].append((m.group(1), m.group(2) or ""))
        else:
            sys.exit(f'classification.yaml:{n}: expected `key:` or `  - "name"  # reason`, got {line!r}')
    return lists


def check(lists):
    seen = {}
    for list_name, items in lists.items():
        for name, _ in items:
            prev = seen.setdefault(key(name), list_name)
            if prev != list_name:
                sys.exit(f"classification.yaml: {name!r} is in both {prev} and {list_name}")
    if not lists["allow"]:
        sys.exit("classification.yaml: allow is empty")


def unique(items):
    out, seen = [], set()
    for name, reason in sorted(items, key=lambda i: key(i[0])):
        if key(name) not in seen:
            seen.add(key(name))
            out.append((name, reason))
    return out


def render(lists):
    allow = "\n".join(f"- {name}" for name, _ in unique(lists["allow"]))

    def withheld(list_name):
        return "\n".join(
            f"- {name}" + (f" — {reason}" if reason else "") for name, reason in unique(lists[list_name])
        )

    return f"""<!-- Generated from classification.yaml by scripts/classification.py render. Do not edit. -->
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

{allow}

### Permissions to leave out

Every other read permission. Unless the B.O.R.I.S team publishes an updated
list, a permission that is not above stays out, including any Cloudflare adds
later. These are left out on purpose:

**Secret-bearing** — credentials, secret values, code, or Zero Trust user and
log data:

{withheld("exclude_secret")}

**Data-bearing** — stored objects, content, logs and traffic records:

{withheld("exclude_data")}

## 2. Register it

Run this in a shell, replacing `<account_id>` (32 hex characters, on the
account's overview page) and the account name. The token is read from the
prompt and passed to `curl` on standard input, so it does not appear in your
shell history or the process list. An account name containing `"` or `\\`
must be escaped for JSON.

```sh
export BORIS_CONNECTION_SECRET='boris_...'
printf 'Cloudflare token: '; read -rs CLOUDFLARE_TOKEN; echo
printf '{{"token":"%s","account_name":"%s"}}' "$CLOUDFLARE_TOKEN" 'Your account name' |
  curl -sS --fail-with-body -X PUT \\
    'https://install.getboris.ai/cloudflare/install/<account_id>' \\
    -H 'Content-Type: application/json' \\
    -H "Authorization: Bearer $BORIS_CONNECTION_SECRET" \\
    --data-binary @-
unset CLOUDFLARE_TOKEN
```

A `2xx` means B.O.R.I.S accepted the token. A `401` means the connection secret
was not accepted, and a `409` that it is already bound to a different account;
neither clears by retrying, so contact the B.O.R.I.S team.

To revoke access, delete the token under **Account API Tokens**.
"""


def fetch_catalogue(token, account_id):
    groups, page = [], 1
    while True:
        req = urllib.request.Request(
            f"https://api.cloudflare.com/client/v4/accounts/{account_id}/tokens/permission_groups?page={page}&per_page=1000",
            headers={"Authorization": f"Bearer {token}"},
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            body = json.load(resp)
        if not body.get("success"):
            sys.exit(f"Cloudflare API error: {body.get('errors')}")
        groups += body.get("result") or []
        info = body.get("result_info") or {}
        if not body.get("result") or page >= int(info.get("total_pages") or 1):
            return groups
        page += 1


def diff(lists, groups):
    classified = {key(n) for items in lists.values() for n, _ in items}
    in_scope = [g for g in groups if set(g.get("scopes") or ()) & set(SCOPES)]
    unclassified = sorted(
        {
            (g["name"], ", ".join(sorted(g["scopes"])))
            for g in in_scope
            if key(g["name"]) not in classified and not key(g["name"]).endswith(WRITE_SUFFIXES)
        },
        key=lambda i: key(i[0]),
    )
    present = {key(g["name"]) for g in in_scope}
    stale = sorted(
        {(n, list_name) for list_name, items in lists.items() for n, _ in items if key(n) not in present},
        key=lambda i: key(i[0]),
    )
    return unclassified, stale


def report(unclassified, stale):
    lines = []
    if unclassified:
        lines += [
            "## Unclassified read groups",
            "",
            "Not granted until classified. Add each to `allow`, `exclude_secret`, `exclude_data` or `write` in `classification.yaml`, then run `scripts/classification.py render`.",
            "",
            "| Group | Scopes |",
            "|---|---|",
        ] + [f"| {n} | {s} |" for n, s in unclassified] + [""]
    if stale:
        lines += [
            "## Classified groups no longer in the catalogue",
            "",
            "Renamed or retired by Cloudflare. Remove them, or classify the new name.",
            "",
            "| Group | List |",
            "|---|---|",
        ] + [f"| {n} | {lst} |" for n, lst in stale] + [""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check", help="validate classification.yaml")
    r = sub.add_parser("render", help="write docs/dashboard-token.md")
    r.add_argument("--check", action="store_true", help="fail if the committed doc is stale")
    d = sub.add_parser("diff-catalogue", help="compare with the live catalogue (CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID)")
    d.add_argument("--out", type=Path, help="write the markdown report here")
    args = parser.parse_args()

    lists = load()
    check(lists)

    if args.command == "render":
        doc = render(lists)
        if args.check:
            if not DASHBOARD_DOC.exists() or DASHBOARD_DOC.read_text() != doc:
                sys.exit("docs/dashboard-token.md is out of date: run scripts/classification.py render")
        else:
            DASHBOARD_DOC.parent.mkdir(exist_ok=True)
            DASHBOARD_DOC.write_text(doc)
    elif args.command == "diff-catalogue":
        groups = fetch_catalogue(os.environ["CLOUDFLARE_API_TOKEN"], os.environ["CLOUDFLARE_ACCOUNT_ID"])
        unclassified, stale = diff(lists, groups)
        text = report(unclassified, stale)
        if args.out:
            args.out.write_text(text)
        print(text or "classification.yaml matches the catalogue")
        # 3 tells the workflow there is something to file.
        sys.exit(3 if text else 0)


if __name__ == "__main__":
    main()
