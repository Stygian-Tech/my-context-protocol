#!/usr/bin/env bash
# Shared local/GitHub CI entrypoint.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export CI="${CI:-true}"
export NEXT_PUBLIC_APP_ENV="${NEXT_PUBLIC_APP_ENV:-test}"

echo "==> Bun workspace install"
bun install --frozen-lockfile

echo "==> Typecheck"
bun run typecheck

echo "==> Lint"
bun run lint

echo "==> Test"
bun run test

echo "==> Build"
bun run build

echo "==> Swift test"
cd "$ROOT/services/mcp-gateway"
mkdir -p .build/ci-logs
swift --version | tee .build/ci-logs/swift-version.txt
swift package clean
swift package resolve
rm -rf .build/index-build 2>/dev/null || true
find .build -name build.db -delete 2>/dev/null || true
env \
  DATABASE_URL="" \
  SUPABASE_DB_URL="" \
  DISABLE_ADMIN_ANALYTICS_ROLLUP_SCHEDULER=1 \
  swift test --skip-update \
    --enable-swift-testing --disable-xctest \
    --no-parallel \
    -Xswiftc -warnings-as-errors

echo "==> Swift release build"
swift build -c release --product App -Xswiftc -warnings-as-errors
