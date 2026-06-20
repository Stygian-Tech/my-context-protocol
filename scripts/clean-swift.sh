#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift package --package-path "$ROOT/services/mcp-gateway" clean
