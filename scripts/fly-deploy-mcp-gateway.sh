#!/usr/bin/env bash
# Deploy services/mcp-gateway to Fly.io for dev or main.
#
# Requires: FLY_API_TOKEN
# Optional: FLY_MCP_GATEWAY_APP_DEV, FLY_MCP_GATEWAY_APP_PROD, FLY_ORG
# Production Supabase CA: SUPABASE_CA_PEM_BASE64 or DATABASE_SSLROOTCERT_BASE64
# Usage: bash scripts/fly-deploy-mcp-gateway.sh dev|main
set -euo pipefail

BRANCH="${1:?usage: fly-deploy-mcp-gateway.sh dev|main}"

if [ -z "${FLY_API_TOKEN:-}" ]; then
  echo '::error::Missing FLY_API_TOKEN.'
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fly_bin() {
  if command -v flyctl >/dev/null 2>&1; then
    printf '%s\n' flyctl
    return
  fi
  if command -v fly >/dev/null 2>&1; then
    printf '%s\n' fly
    return
  fi
  echo '::error::Install flyctl to deploy: https://fly.io/docs/flyctl/install/' >&2
  exit 1
}

stage_prod_database_ca_secret() {
  [ "$BRANCH" = "main" ] || return 0

  local app="${FLY_MCP_GATEWAY_APP_PROD:-my-context-protocol-prod-gateway}"
  local ca_base64="${SUPABASE_CA_PEM_BASE64:-${DATABASE_SSLROOTCERT_BASE64:-}}"

  if [ -z "$ca_base64" ]; then
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
      echo '::error::Missing SUPABASE_CA_PEM_BASE64. Add the base64-encoded Supabase server root certificate as a GitHub Actions secret so CI can stage DATABASE_SSLROOTCERT_BASE64 before production deploy.'
      exit 1
    fi
    echo '::warning::SUPABASE_CA_PEM_BASE64 is unset; assuming DATABASE_SSLROOTCERT_BASE64 is already configured in Fly secrets.'
    return 0
  fi

  echo "::notice::Staging production Postgres CA trust root secret for ${app}"
  "$(fly_bin)" secrets set --stage --app "$app" \
    "DATABASE_SSLROOTCERT_BASE64=$ca_base64"
}

echo "::notice::Fly MCP gateway deploy (${BRANCH})"
stage_prod_database_ca_secret
exec bash "$ROOT/services/mcp-gateway/deploy.sh" "$BRANCH"
