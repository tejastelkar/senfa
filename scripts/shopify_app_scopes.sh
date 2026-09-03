#!/usr/bin/env bash
# Deploy the "Senfa Automation" app config and verify the scopes the store
# actually granted.
#
# Edit `scopes` in shopify-app/shopify.app.toml first, then run this. It:
#   1. deploys the app config (creates a new app version in the Dev Dashboard),
#   2. drops the cached Admin API token so the next call re-authenticates,
#   3. re-reads the granted scopes and diffs them against what was declared.
#
# Because the app uses the modern install flow (use_legacy_install_flow = false)
# scopes are normally auto-granted on deploy. If the diff still reports missing
# scopes, open the app in the Shopify admin and accept the new permissions:
#   Settings > Apps and sales channels > Senfa Automation
#
# Usage:
#   scripts/shopify_app_scopes.sh            # deploy, then verify
#   scripts/shopify_app_scopes.sh --check    # verify only, no deploy
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/shopify-app"
cd "$ROOT"

if [ ! -f "$APP_DIR/shopify.app.toml" ]; then
  echo "error: $APP_DIR/shopify.app.toml not found." >&2
  echo "       Recreate it with:" >&2
  echo "       shopify app config link --client-id \$SHOPIFY_CLIENT_ID --path shopify-app" >&2
  exit 1
fi

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

if [ "$CHECK_ONLY" -eq 0 ]; then
  echo "==> Deploying app config from shopify-app/shopify.app.toml"
  # --allow-updates: required in non-interactive shells; adds/updates config but
  # refuses to delete anything (unlike --allow-deletes).
  shopify app deploy \
    --path "$APP_DIR" \
    --allow-updates \
    --message "Update Admin API access scopes"
  echo
  echo "==> Clearing cached Admin API token"
  rm -f "$ROOT/.cache/shopify-admin-token.json"
fi

echo "==> Reading granted scopes from the Admin API"
GRANTED="$("$ROOT/scripts/shopify_admin.sh" -r \
  'query { currentAppInstallation { accessScopes { handle } } }')"

APP_DIR="$APP_DIR" python3 - "$GRANTED" <<'PY'
import json, os, re, sys

# tomllib only exists on Python 3.11+, and macOS ships 3.9, so pull the scopes
# value out directly. Handles both scopes = "..." and scopes = """...""".
toml_path = os.path.join(os.environ["APP_DIR"], "shopify.app.toml")
with open(toml_path) as fh:
    toml = fh.read()

m = re.search(r'^\s*scopes\s*=\s*"""(.*?)"""', toml, re.M | re.S) or \
    re.search(r'^\s*scopes\s*=\s*"([^"]*)"', toml, re.M)
if not m:
    sys.stderr.write("error: no access_scopes.scopes found in %s\n" % toml_path)
    sys.exit(1)
declared = {s.strip() for s in m.group(1).split(",") if s.strip()}

try:
    resp = json.loads(sys.argv[1])
    granted = {
        s["handle"]
        for s in resp["data"]["currentAppInstallation"]["accessScopes"]
    }
except Exception:
    sys.stderr.write("error: could not read granted scopes:\n%s\n" % sys.argv[1][:800])
    sys.exit(1)

# A granted write_x implies read_x, and Shopify does not always echo the read
# half back, so don't report those as missing.
implied = {"read_" + s[len("write_"):] for s in granted if s.startswith("write_")}
missing = sorted(declared - granted - implied)
extra = sorted(granted - declared)

print("\ndeclared: %d scopes    granted: %d scopes" % (len(declared), len(granted)))
if extra:
    print("\ngranted but not declared (%d):" % len(extra))
    for s in extra:
        print("  + %s" % s)
if missing:
    print("\nNOT granted (%d):" % len(missing))
    for s in missing:
        print("  - %s" % s)
    print("\nOpen the app in the Shopify admin and accept the new permissions:")
    print("  Settings > Apps and sales channels > Senfa Automation")
    sys.exit(1)

print("\nAll declared scopes are granted.")
PY
