#!/usr/bin/env bash
# Usage: railway-deploy-development.sh dev Gateway|Web|all <40-char-sha>
set -euo pipefail

BRANCH="${1:?usage: railway-deploy-development.sh dev Gateway|Web|all sha}"
SELECTION="${2:?usage: railway-deploy-development.sh dev Gateway|Web|all sha}"
EXPECTED_SHA="${3:?usage: railway-deploy-development.sh dev Gateway|Web|all sha}"

[ "$BRANCH" = "dev" ] || {
  echo "Development Railway deployments are allowed from dev only." >&2
  exit 1
}

exec "$(cd "$(dirname "$0")" && pwd)/railway-deploy.sh" dev dev "$SELECTION" "$EXPECTED_SHA"
