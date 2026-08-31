#!/usr/bin/env bash
# Deploy an exact Git commit to one Railway environment.
# Usage: railway-deploy.sh dev|production dev|main Gateway|Web|all <40-char-sha>
set -euo pipefail

TARGET_ENVIRONMENT="${1:?usage: railway-deploy.sh dev|production dev|main Gateway|Web|all sha}"
EXPECTED_BRANCH="${2:?usage: railway-deploy.sh dev|production dev|main Gateway|Web|all sha}"
SELECTION="${3:?usage: railway-deploy.sh dev|production dev|main Gateway|Web|all sha}"
EXPECTED_SHA="${4:?usage: railway-deploy.sh dev|production dev|main Gateway|Web|all sha}"
PROJECT_ID="${RAILWAY_PROJECT_ID:-3647f696-1766-459a-ac3f-0482e5a1f26c}"
EXPECTED_PROJECT_ID="3647f696-1766-459a-ac3f-0482e5a1f26c"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
  echo "$1" >&2
  exit 1
}

case "$TARGET_ENVIRONMENT:$EXPECTED_BRANCH" in
  dev:dev|production:main) ;;
  *) fail "Environment and branch must be dev:dev or production:main." ;;
esac

case "$SELECTION" in
  Gateway|Web|all) ;;
  *) fail "Unknown service selection: $SELECTION (expected Gateway, Web, or all)." ;;
esac

[[ "$EXPECTED_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "Expected a full lowercase 40-character Git SHA."
[ "$PROJECT_ID" = "$EXPECTED_PROJECT_ID" ] || fail "Refusing to deploy an unexpected Railway project ID."
command -v railway >/dev/null 2>&1 || fail "Install the Railway CLI before deploying."

if [ -n "${GITHUB_ACTIONS:-}" ]; then
  [ -n "${RAILWAY_TOKEN:-}" ] || fail "Missing environment-scoped RAILWAY_TOKEN."
else
  railway whoami >/dev/null 2>&1 || fail "The local Railway CLI is not authenticated."
fi

cd "$ROOT"
ACTUAL_SHA="$(git rev-parse HEAD)"
[ "$ACTUAL_SHA" = "$EXPECTED_SHA" ] || fail "HEAD does not match the requested deployment SHA."
[ -z "$(git status --porcelain)" ] || fail "Refusing to deploy a dirty worktree."

if [ -n "${GITHUB_ACTIONS:-}" ]; then
  [ "${GITHUB_REF_NAME:-}" = "$EXPECTED_BRANCH" ] || fail "GitHub ref does not match the expected branch."
  [ "${GITHUB_SHA:-}" = "$EXPECTED_SHA" ] || fail "GitHub SHA does not match the requested deployment SHA."
else
  [ "$(git branch --show-current)" = "$EXPECTED_BRANCH" ] || fail "Local checkout is not on the expected branch."
fi

REMOTE_SHA="$(git rev-parse "refs/remotes/origin/$EXPECTED_BRANCH")"
[ "$REMOTE_SHA" = "$EXPECTED_SHA" ] || fail "The requested SHA is not the current origin/$EXPECTED_BRANCH tip."

deploy_service() {
  local service="$1"
  railway up "$ROOT" \
    --ci \
    --project "$PROJECT_ID" \
    --environment "$TARGET_ENVIRONMENT" \
    --service "$service" \
    --message "${TARGET_ENVIRONMENT} ${service} ${EXPECTED_SHA}"
}

case "$SELECTION" in
  Gateway) deploy_service Gateway ;;
  Web) deploy_service Web ;;
  all)
    deploy_service Gateway
    deploy_service Web
    ;;
esac
