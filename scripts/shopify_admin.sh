#!/usr/bin/env bash
# Runs an Admin GraphQL query/mutation against the senfa store.
# Usage: scripts/shopify_admin.sh '<graphql query/mutation string>' '<json variables (optional)>'
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

QUERY="$1"
if [ -n "${2:-}" ]; then
  VARS="$2"
else
  VARS="{}"
fi

TOKEN=$(curl -s -X POST "https://${SHOPIFY_STORE_DOMAIN}/admin/oauth/access_token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=${SHOPIFY_CLIENT_ID}&client_secret=${SHOPIFY_CLIENT_SECRET}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")

python3 -c "
import json, sys
print(json.dumps({'query': sys.argv[1], 'variables': json.loads(sys.argv[2])}))
" "$QUERY" "$VARS" > /tmp/senfa_gql_payload.json

curl -s -X POST "https://${SHOPIFY_STORE_DOMAIN}/admin/api/2024-10/graphql.json" \
  -H "X-Shopify-Access-Token: ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d @/tmp/senfa_gql_payload.json
