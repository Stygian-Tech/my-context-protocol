#!/usr/bin/env bash
# Deploy one or both MyContextProtocol production services to Railway from main.
# Usage: bash scripts/railway-deploy-production.sh main Gateway|Web|all
set -euo pipefail

BRANCH="${1:?usage: railway-deploy-production.sh main Gateway|Web|all}"
SELECTION="${2:?usage: railway-deploy-production.sh main Gateway|Web|all}"

if [ "$BRANCH" != "main" ]; then
  echo "Production Railway deployments are allowed from main only." >&2
  exit 1
fi
if [ -z "${RAILWAY_TOKEN:-}" ]; then
  echo "Missing production-scoped RAILWAY_TOKEN." >&2
  exit 1
fi
if ! command -v railway >/dev/null 2>&1; then
  echo "Install the Railway CLI before deploying." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ID="${RAILWAY_PROJECT_ID:-3647f696-1766-459a-ac3f-0482e5a1f26c}"
ENVIRONMENT="${RAILWAY_ENVIRONMENT:-production}"

deploy_service() {
  local service="$1"
  railway up "$ROOT" \
    --ci \
    --project "$PROJECT_ID" \
    --environment "$ENVIRONMENT" \
    --service "$service" \
    --message "GitHub main production deploy: ${service}"
}

case "$SELECTION" in
  Gateway|Web) deploy_service "$SELECTION" ;;
  all)
    deploy_service Gateway
    deploy_service Web
    ;;
  *)
    echo "Unknown service selection: $SELECTION (expected Gateway, Web, or all)." >&2
    exit 1
    ;;
esac
