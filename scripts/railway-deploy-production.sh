#!/usr/bin/env bash
# Deploy an exact main commit to one or both production Railway services.
# Usage: railway-deploy-production.sh main Gateway|Web|all <40-char-sha>
set -euo pipefail

BRANCH="${1:?usage: railway-deploy-production.sh main Gateway|Web|all sha}"
SELECTION="${2:?usage: railway-deploy-production.sh main Gateway|Web|all sha}"
EXPECTED_SHA="${3:?usage: railway-deploy-production.sh main Gateway|Web|all sha}"

if [ "$BRANCH" != "main" ]; then
  echo "Production Railway deployments are allowed from main only." >&2
  exit 1
fi
exec "$(cd "$(dirname "$0")" && pwd)/railway-deploy.sh" production main "$SELECTION" "$EXPECTED_SHA"
