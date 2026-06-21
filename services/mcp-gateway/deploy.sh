#!/usr/bin/env bash
# Deploy the MCP gateway from services/mcp-gateway.
#
# Usage: bash deploy.sh dev|main
set -euo pipefail

SERVICE_DIR="$(cd "$(dirname "$0")" && pwd)"
BRANCH="${1:?usage: deploy.sh dev|main}"
shift

if [ "$BRANCH" = "main" ]; then
  APP="${FLY_MCP_GATEWAY_APP_PROD:-my-context-protocol-prod-gateway}"
  APP_ENV_VALUE="prod"
  DATABASE_INSECURE_TLS_VALUE="0"
else
  APP="${FLY_MCP_GATEWAY_APP_DEV:-my-context-protocol-dev-gateway}"
  APP_ENV_VALUE="dev"
  DATABASE_INSECURE_TLS_VALUE="1"
fi

cd "$SERVICE_DIR"

ENV_ARGS=(
  --env "APP_ENV=$APP_ENV_VALUE"
  --env "DATABASE_INSECURE_TLS=$DATABASE_INSECURE_TLS_VALUE"
)

if command -v flyctl >/dev/null 2>&1; then
  exec flyctl deploy --config fly.toml --app "$APP" --remote-only "${ENV_ARGS[@]}" "$@"
fi
if command -v fly >/dev/null 2>&1; then
  exec fly deploy --config fly.toml --app "$APP" --remote-only "${ENV_ARGS[@]}" "$@"
fi

echo "Install flyctl to deploy: https://fly.io/docs/flyctl/install/" >&2
exit 1
