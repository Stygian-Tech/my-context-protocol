# Test Plans

| Surface | Local command | CI job |
|---|---|---|
| Full workspace | `bash scripts/ci.sh` | `CI / Test and build` |
| Web dashboard | `bun --cwd apps/web run lint && bun --cwd apps/web run typecheck && bun --cwd apps/web run test:ci && bun --cwd apps/web run build` | `CI / Test and build` |
| Shared TypeScript packages | `bun run typecheck --filter=@mycontext/web-client` | `CI / Test and build` |
| MCP gateway | `cd services/mcp-gateway && swift test --enable-swift-testing --disable-xctest --no-parallel -Xswiftc -warnings-as-errors` | `CI / Test and build` |
| MCP gateway release build | `cd services/mcp-gateway && swift build -c release --product App -Xswiftc -warnings-as-errors` | `CI / Test and build` |
| Fly config | `flyctl config validate --config services/mcp-gateway/fly.toml` | Manual/local until Fly credentials are present |

CI uses `scripts/ci-detect-changes.sh` for path detection and `scripts/ci.sh` as the shared local/GitHub entrypoint.
