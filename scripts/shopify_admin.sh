#!/usr/bin/env bash
# Run an Admin GraphQL query/mutation against the Senfa store.
#
# Credentials come from .env (SHOPIFY_STORE_DOMAIN / SHOPIFY_CLIENT_ID /
# SHOPIFY_CLIENT_SECRET) via the client_credentials grant. The access token is
# cached in .cache/shopify-admin-token.json until shortly before it expires, so
# repeated calls cost one HTTP request instead of two.
#
# Usage:
#   scripts/shopify_admin.sh '<query>' ['<json variables>']
#   scripts/shopify_admin.sh -f query.graphql [-v vars.json]
#   scripts/shopify_admin.sh < query.graphql
#
# Options:
#   -f FILE   read the query from FILE
#   -v FILE   read variables (JSON) from FILE
#   -r        print raw response instead of pretty-printed JSON
#   -a VER    override the API version (default: $SHOPIFY_API_VERSION or 2026-07)
#
# Exits non-zero when the response contains GraphQL `errors` or `userErrors`,
# so it is safe to use in scripts and CI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -f .env ]; then
  echo "error: .env not found in $ROOT (see .env.example)" >&2
  exit 1
fi
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${SHOPIFY_STORE_DOMAIN:?missing SHOPIFY_STORE_DOMAIN in .env}"
: "${SHOPIFY_CLIENT_ID:?missing SHOPIFY_CLIENT_ID in .env}"
: "${SHOPIFY_CLIENT_SECRET:?missing SHOPIFY_CLIENT_SECRET in .env}"

API_VERSION="${SHOPIFY_API_VERSION:-2026-07}"
QUERY_FILE=""
VARS_FILE=""
RAW=0

while getopts ":f:v:a:r" opt; do
  case "$opt" in
    f) QUERY_FILE="$OPTARG" ;;
    v) VARS_FILE="$OPTARG" ;;
    a) API_VERSION="$OPTARG" ;;
    r) RAW=1 ;;
    \?) echo "error: unknown option -$OPTARG" >&2; exit 2 ;;
    :) echo "error: -$OPTARG requires a value" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

if [ -n "$QUERY_FILE" ]; then
  QUERY="$(cat "$QUERY_FILE")"
elif [ $# -gt 0 ]; then
  QUERY="$1"
  shift
elif [ ! -t 0 ]; then
  QUERY="$(cat)"
else
  echo "error: no query given (pass a query string, -f FILE, or pipe it in)" >&2
  exit 2
fi

if [ -n "$VARS_FILE" ]; then
  VARS="$(cat "$VARS_FILE")"
elif [ $# -gt 0 ] && [ -n "$1" ]; then
  VARS="$1"
else
  VARS="{}"
fi

CACHE_DIR="$ROOT/.cache"
TOKEN_CACHE="$CACHE_DIR/shopify-admin-token.json"
mkdir -p "$CACHE_DIR"

token_from_cache() {
  [ -f "$TOKEN_CACHE" ] || return 1
  python3 - "$TOKEN_CACHE" "$SHOPIFY_STORE_DOMAIN" "$SHOPIFY_CLIENT_ID" <<'PY'
import json, sys, time
try:
    c = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
# Invalidate if the store or app changed, or if we're within 60s of expiry.
if c.get("store") != sys.argv[2] or c.get("client_id") != sys.argv[3]:
    sys.exit(1)
if float(c.get("expires_at", 0)) - 60 <= time.time():
    sys.exit(1)
print(c["access_token"])
PY
}

fetch_token() {
  local response
  response="$(curl -sS -X POST "https://${SHOPIFY_STORE_DOMAIN}/admin/oauth/access_token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_id=${SHOPIFY_CLIENT_ID}" \
    --data-urlencode "client_secret=${SHOPIFY_CLIENT_SECRET}")"
  TOKEN_CACHE="$TOKEN_CACHE" python3 - "$response" "$SHOPIFY_STORE_DOMAIN" "$SHOPIFY_CLIENT_ID" <<'PY'
import json, os, sys, time
try:
    d = json.loads(sys.argv[1])
except Exception:
    sys.stderr.write("error: token endpoint returned non-JSON:\n%s\n" % sys.argv[1][:500])
    sys.exit(1)
if "access_token" not in d:
    sys.stderr.write("error: token request failed: %s\n" % json.dumps(d))
    sys.exit(1)
path = os.environ["TOKEN_CACHE"]
with open(path, "w") as fh:
    json.dump({
        "store": sys.argv[2],
        "client_id": sys.argv[3],
        "access_token": d["access_token"],
        "scope": d.get("scope", ""),
        "expires_at": time.time() + float(d.get("expires_in", 3600)),
    }, fh)
os.chmod(path, 0o600)
print(d["access_token"])
PY
}

TOKEN="$(token_from_cache || fetch_token)"

PAYLOAD="$(python3 - "$QUERY" "$VARS" <<'PY'
import json, sys
try:
    variables = json.loads(sys.argv[2] or "{}")
except json.JSONDecodeError as e:
    sys.stderr.write("error: variables are not valid JSON: %s\n" % e)
    sys.exit(2)
print(json.dumps({"query": sys.argv[1], "variables": variables}))
PY
)"

RESPONSE="$(curl -sS -X POST \
  "https://${SHOPIFY_STORE_DOMAIN}/admin/api/${API_VERSION}/graphql.json" \
  -H "X-Shopify-Access-Token: ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")"

RAW="$RAW" python3 - "$RESPONSE" <<'PY'
import json, os, re, sys
raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    sys.stdout.write(raw + "\n")
    sys.exit(1)

print(raw if os.environ.get("RAW") == "1" else json.dumps(data, indent=2))

failed = "errors" in data
# Mutations report validation failures in `userErrors`/`*UserErrors` instead.
def walk(node):
    global failed
    if isinstance(node, dict):
        for k, v in node.items():
            if re.fullmatch(r"\w*[uU]serErrors", k) and v:
                failed = True
            walk(v)
    elif isinstance(node, list):
        for v in node:
            walk(v)
walk(data.get("data"))
sys.exit(1 if failed else 0)
PY
