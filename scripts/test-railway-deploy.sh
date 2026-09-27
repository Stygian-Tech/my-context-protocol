#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/repo/scripts" "$FIXTURE/bin"
cp "$ROOT/scripts/railway-deploy.sh" "$FIXTURE/repo/scripts/railway-deploy.sh"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'case "${1:-}" in' \
  '  whoami) exit "${STUB_WHOAMI_EXIT:-0}" ;;' \
  '  up) printf "%s\\n" "$*" >> "${STUB_RAILWAY_LOG:?}" ;;' \
  '  *) exit 2 ;;' \
  'esac' > "$FIXTURE/bin/railway"
chmod +x "$FIXTURE/bin/railway" "$FIXTURE/repo/scripts/railway-deploy.sh"

git -C "$FIXTURE/repo" init -q -b dev
git -C "$FIXTURE/repo" config user.email "ci@example.invalid"
git -C "$FIXTURE/repo" config user.name "CI"
git -C "$FIXTURE/repo" config commit.gpgSign false
git -C "$FIXTURE/repo" add scripts/railway-deploy.sh
git -C "$FIXTURE/repo" commit -q -m "fixture"
SHA="$(git -C "$FIXTURE/repo" rev-parse HEAD)"
git -C "$FIXTURE/repo" update-ref refs/remotes/origin/dev "$SHA"

export PATH="$FIXTURE/bin:$PATH"
export STUB_RAILWAY_LOG="$FIXTURE/railway.log"

(
  cd "$FIXTURE/repo"
  env -u GITHUB_ACTIONS -u RAILWAY_TOKEN \
    scripts/railway-deploy.sh dev dev Gateway "$SHA"
)
grep -F -- "--environment dev --service Gateway" "$STUB_RAILWAY_LOG" >/dev/null

if (
  cd "$FIXTURE/repo"
  GITHUB_ACTIONS=1 GITHUB_REF_NAME=dev GITHUB_SHA="$SHA" \
    env -u RAILWAY_TOKEN scripts/railway-deploy.sh dev dev Gateway "$SHA"
) 2>"$FIXTURE/ci-error.log"; then
  echo "Expected CI deployment without RAILWAY_TOKEN to fail." >&2
  exit 1
fi
grep -F "Missing environment-scoped RAILWAY_TOKEN." "$FIXTURE/ci-error.log" >/dev/null

if (
  cd "$FIXTURE/repo"
  STUB_WHOAMI_EXIT=1 env -u GITHUB_ACTIONS -u RAILWAY_TOKEN \
    scripts/railway-deploy.sh dev dev Gateway "$SHA"
) 2>"$FIXTURE/local-error.log"; then
  echo "Expected unauthenticated local deployment to fail." >&2
  exit 1
fi
grep -F "The local Railway CLI is not authenticated." "$FIXTURE/local-error.log" >/dev/null

echo "Railway deployment authentication tests passed."
