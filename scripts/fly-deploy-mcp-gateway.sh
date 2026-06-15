#!/usr/bin/env bash
# Deploy services/mcp-gateway to Fly.io for dev or main.
#
# Requires: FLY_API_TOKEN
# Optional: FLY_MCP_GATEWAY_APP_DEV, FLY_MCP_GATEWAY_APP_PROD, FLY_ORG
# Usage: bash scripts/fly-deploy-mcp-gateway.sh dev|main
set -euo pipefail

BRANCH="${1:?usage: fly-deploy-mcp-gateway.sh dev|main}"

if [ -z "${FLY_API_TOKEN:-}" ]; then
  echo '::error::Missing FLY_API_TOKEN.'
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "::notice::Fly MCP gateway deploy (${BRANCH})"
exec bash "$ROOT/services/mcp-gateway/deploy.sh" "$BRANCH"
