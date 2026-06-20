#!/usr/bin/env bash
# Detect changed path filters for CI without depending on a marketplace action.
set -euo pipefail

BASE=""
HEAD="${GITHUB_SHA:?GITHUB_SHA is required}"
MATCH_ALL=0

case "${GITHUB_EVENT_NAME:-}" in
  pull_request|pull_request_target)
    BASE="${GITHUB_EVENT_PULL_REQUEST_BASE_SHA:-}"
    if [ -z "$BASE" ] && [ -n "${GITHUB_BASE_REF:-}" ]; then
      BASE="$(git merge-base "$HEAD" "origin/${GITHUB_BASE_REF}")"
    fi
    if [ -z "$BASE" ]; then
      MATCH_ALL=1
    fi
    ;;
  push)
    BASE="${GITHUB_EVENT_BEFORE:-}"
    if [ -z "$BASE" ] || [ "$BASE" = "0000000000000000000000000000000000000000" ]; then
      MATCH_ALL=1
    fi
    ;;
  *)
    MATCH_ALL=1
    ;;
esac

to_pathspec() {
  local spec="$1"
  if [[ "$spec" == *"*"* ]]; then
    printf ':(glob)%s' "$spec"
  else
    printf '%s' "$spec"
  fi
}

filter_changed() {
  local name="$1"
  shift
  local out="${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

  if [ "$MATCH_ALL" = "1" ]; then
    echo "${name}=true" >> "$out"
    return
  fi

  local spec pathspec
  for spec in "$@"; do
    pathspec="$(to_pathspec "$spec")"
    if [ -n "$(git diff --name-only "$BASE" "$HEAD" -- "$pathspec")" ]; then
      echo "${name}=true" >> "$out"
      return
    fi
  done

  echo "${name}=false" >> "$out"
}

filter_changed web \
  'apps/web/**' \
  'packages/**' \
  'package.json' \
  'bun.lock' \
  'turbo.json' \
  'scripts/ci.sh' \
  'scripts/ci-detect-changes.sh' \
  '.github/workflows/ci.yml'

filter_changed mcp_gateway \
  'services/mcp-gateway/**' \
  'scripts/ci.sh' \
  'scripts/ci-detect-changes.sh' \
  'scripts/fly-deploy-mcp-gateway.sh' \
  '.github/workflows/ci.yml'

filter_changed packages \
  'packages/**' \
  'package.json' \
  'bun.lock' \
  'turbo.json' \
  '.github/workflows/ci.yml'

filter_changed ci \
  'scripts/**' \
  '.github/workflows/**' \
  'package.json' \
  'bun.lock' \
  'turbo.json'
