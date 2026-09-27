#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/repo/scripts" "$FIXTURE/bin"
cp "$ROOT/scripts/railway-deploy.sh" "$FIXTURE/repo/scripts/railway-deploy.sh"

# The stub records `up` calls and, once a service has been uploaded, reports a new
# deployment for it with STUB_<SERVICE>_STATUS (default SUCCESS).
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'service=""; message=""' \
  'args=("$@")' \
  'for ((i = 0; i < ${#args[@]}; i++)); do' \
  '  case "${args[$i]}" in' \
  '    --service) service="${args[$((i + 1))]}" ;;' \
  '    --message) message="${args[$((i + 1))]}" ;;' \
  '  esac' \
  'done' \
  'case "${1:-}" in' \
  '  whoami) exit "${STUB_WHOAMI_EXIT:-0}" ;;' \
  '  up)' \
  '    printf "%s\\n" "$*" >> "${STUB_RAILWAY_LOG:?}"' \
  '    printf "%s\\n" "$message" > "${STUB_RAILWAY_LOG}.$service"' \
  '    ;;' \
  '  deployment)' \
  '    status_var="STUB_$(printf "%s" "$service" | tr "[:lower:]" "[:upper:]")_STATUS"' \
  '    old="{\"id\":\"old\",\"status\":\"SUCCESS\",\"meta\":{\"cliMessage\":\"old\"}}"' \
  '    if [ -f "${STUB_RAILWAY_LOG}.$service" ]; then' \
  '      jq -cn --arg m "$(cat "${STUB_RAILWAY_LOG}.$service")" --arg s "${!status_var:-SUCCESS}" --argjson old "$old" \' \
  '        "[{id: \"new\", status: \$s, meta: {cliMessage: \$m}}, \$old]"' \
  '    else' \
  '      printf "[%s]\\n" "$old"' \
  '    fi' \
  '    ;;' \
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
export RAILWAY_DEPLOY_POLL_SECONDS=0

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

rm -f "$STUB_RAILWAY_LOG"*
if (
  cd "$FIXTURE/repo"
  STUB_GATEWAY_STATUS=FAILED env -u GITHUB_ACTIONS -u RAILWAY_TOKEN \
    scripts/railway-deploy.sh dev dev all "$SHA"
) 2>"$FIXTURE/unhealthy-error.log"; then
  echo "Expected an unhealthy Gateway deployment to fail the rollout." >&2
  exit 1
fi
grep -F "dev Gateway deployment ended as FAILED" "$FIXTURE/unhealthy-error.log" >/dev/null
if grep -F -- "--service Web" "$STUB_RAILWAY_LOG" >/dev/null; then
  echo "Web must not deploy after the Gateway deployment fails." >&2
  exit 1
fi

rm -f "$STUB_RAILWAY_LOG"*
(
  cd "$FIXTURE/repo"
  env -u GITHUB_ACTIONS -u RAILWAY_TOKEN scripts/railway-deploy.sh dev dev all "$SHA"
) >/dev/null
grep -F -- "--service Web" "$STUB_RAILWAY_LOG" >/dev/null

echo "Railway deployment tests passed."
