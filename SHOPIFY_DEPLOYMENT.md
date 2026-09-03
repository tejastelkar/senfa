# Shopify Setup & Deployment Guide

How to talk to the Senfa store from this repo — both the theme (Shopify CLI) and
the data/admin side (Admin GraphQL API).

## Store facts

| | |
|---|---|
| Public domain | `senfa.shop` |
| myshopify domain | `0pjcz9-vg.myshopify.com` |
| Store owner account | `senfasocial@gmail.com` |
| Custom app (API access) | `Senfa Automation` |
| GitHub repo | https://github.com/tejastelkar/senfa.git |

Themes on the store (`shopify theme list`, verified 2026-09-03):

| Theme | Role | ID |
|---|---|---|
| `Dawn` | **live** — what this repo tracks | `137869197521` |
| `Horizon` | unpublished — a separate theme, not a copy of this one | `137864839377` |

There is no staging theme yet. To create one:
`shopify theme push --unpublished --theme "Senfa staging"`, then put its ID in
the `staging` environment in `shopify.theme.toml`.

`senfa-2.myshopify.com` is an old handle for the same store and still redirects
to `senfa.shop`. Always use `0pjcz9-vg.myshopify.com` — that's what the Admin API
reports as `myshopifyDomain`.

---

## 1. Shopify CLI

Installed globally via npm (`shopify --version` → 4.7.x).

### Store targeting

`shopify.theme.toml` in the repo root defines the environments, so **you never
pass `--store` or `--theme` by hand**:

| Environment | Target |
|---|---|
| `default` | Senfa store, no theme preselected — applied automatically when no `-e` is given |
| `-e live` | The live theme (resolved by role, plus `allow-live`) |
| `-e dev` | Your per-developer development theme |
| `-e staging` | A staging theme — none exists yet; create one and set its ID in the toml first |

The `default` environment matters: the CLI's *global* store setting points at a
different project's store, and without `default` a bare `shopify theme …` here
would silently target that store.

### Authentication

There is no `--store` flag on `shopify auth login`. Auth happens implicitly on
the first `theme`/`app` command — it prints a device code link, you approve it in
the browser, and the command continues:

```bash
shopify theme list
```

The CLI holds **one** logged-in account at a time. If you're logged in as a
different account you'll get *"Looks like you don't have access to this dev
store"* — that's an account problem, not a store problem. Fix it with:

```bash
shopify auth logout
shopify theme list          # log in again, as senfasocial@gmail.com
```

Note that `logout` also drops the session for any other Shopify project on this
machine; those just need one more browser approval next time.

### Common commands

```bash
shopify theme list                  # all themes + IDs and roles
shopify theme dev                   # local preview server with hot reload
shopify theme pull -e live          # pull live settings/templates into the repo
shopify theme push -e dev           # deploy to your development theme
shopify theme push -e live          # deploy to production
shopify theme push -e live --only templates/index.json   # deploy a subset
shopify theme check                 # lint Liquid before pushing
```

`push` deletes remote files that don't exist locally. Pass `--nodelete` when you
only mean to add or update.

### Recommended flow

1. `shopify theme pull -e live` first if the theme was edited in the admin —
   otherwise a push will overwrite those edits.
2. Work locally, preview with `shopify theme dev`.
3. `shopify theme check`.
4. `shopify theme push -e dev`, review the preview URL.
5. `shopify theme push -e live`.
6. Commit and push to `main`.

### Alternative: GitHub integration

The repo can also be connected under **Online Store > Themes > Add theme >
Connect from GitHub**, in which case pushing to `main` deploys automatically.

---

## 2. Admin GraphQL API

Access comes from the `Senfa Automation` custom app using the OAuth
`client_credentials` grant — no token is stored by hand and none expire in your
face. Credentials live in `.env` (gitignored; see `.env.example`):

```
SHOPIFY_STORE_DOMAIN=0pjcz9-vg.myshopify.com
SHOPIFY_CLIENT_ID=…
SHOPIFY_CLIENT_SECRET=…
SHOPIFY_API_VERSION=2026-07
```

### Running queries

```bash
# inline query
scripts/shopify_admin.sh 'query { shop { name primaryDomain { host } } }'

# with variables
scripts/shopify_admin.sh 'query($n:Int!){ products(first:$n){ nodes { title } } }' '{"n":5}'

# from files, or piped in
scripts/shopify_admin.sh -f query.graphql -v vars.json
scripts/shopify_admin.sh < query.graphql

# one-off API version override
scripts/shopify_admin.sh -a 2026-04 'query { shop { name } }'
```

The script pretty-prints the response, caches the access token in
`.cache/shopify-admin-token.json` (gitignored, `chmod 600`) until just before it
expires, and **exits non-zero** if the response contains `errors` or any
`userErrors` — so it's safe in scripts and CI. Use `-r` for the raw response.

### API version

Pinned by `SHOPIFY_API_VERSION` in `.env`, currently `2026-07`. Shopify supports
each version for ~12 months; check what's available with:

```bash
scripts/shopify_admin.sh 'query { publicApiVersions { handle displayName supported } }'
```

---

## 3. App configuration & access scopes

The app is configured as code in `shopify-app/shopify.app.toml`. It sits in a
subdirectory on purpose: `shopify app *` commands run against that directory,
while `shopify theme *` commands run against the repo root, so the two projects
don't collide.

App identifiers: org `211721500`, app `403850231809`
(https://dev.shopify.com/dashboard/211721500/apps/403850231809).

### Current grant

**59 scopes, verified granted 2026-09-03.** Full read/write across products,
publications, inventory, files, themes, content, online store navigation,
orders, draft orders, customers, all four fulfillment-order scopes, returns,
discounts, price rules, gift cards, markets, locales, translations, shipping,
script tags, legal policies, marketing events, payment terms and checkouts, plus
read on locations. Every Admin API resource probed came back accessible.

Six scopes need separate Shopify approval and are deliberately excluded,
because one invalid or unapproved scope fails the entire deploy:
`read_all_orders`, `read_reports`, `read_shopify_payments_payouts`,
`read_shopify_payments_disputes`, `write_gdpr_data_request`,
`write_customer_data_erasure`.

### Changing scopes

Edit `scopes` in `shopify-app/shopify.app.toml`, then:

```bash
scripts/shopify_app_scopes.sh            # deploy, then verify the grant
scripts/shopify_app_scopes.sh --check    # verify only, no deploy
```

The script deploys the config (releasing a new app version), clears the cached
token, then diffs declared scopes against what the store actually granted and
exits non-zero if any are missing. A granted `write_x` implies `read_x`, which
the diff accounts for.

**Deploying is not the same as granting.** A deploy releases a new app version,
but the existing store install keeps its old permissions until someone approves
the new ones in a browser:

```
https://admin.shopify.com/store/0pjcz9-vg/oauth/install?client_id=<client_id>
```

Failing that, the Shopify admin shows an update-permissions prompt under
**Settings > Apps and sales channels > Senfa Automation**. Run
`scripts/shopify_app_scopes.sh --check` afterwards to confirm.

Any field you lack a scope for returns `ACCESS_DENIED` and names the scope it
wants, so you never have to guess.

### Security note

These credentials now carry full read/write over orders and customer PII. A
leaked `.env` exposes customer data, not just a product catalog. `.env` is
gitignored — keep it that way, and prefer trimming the scope list back to what
is actually automated over leaving everything enabled.

Theme files are read and written through the CLI, not this API, so `read_themes`
is rarely the tool you want for theme work.
