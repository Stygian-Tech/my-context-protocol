# Test Plans

| Surface | Local command | CI job |
|---|---|---|
| Full workspace | `bash scripts/ci.sh` | `CI / Test and build` |
| Web dashboard | `bun --cwd apps/web run lint && bun --cwd apps/web run typecheck && bun --cwd apps/web run test:ci && bun --cwd apps/web run build` | `CI / Test and build` |
| Shared TypeScript packages | `bun run typecheck --filter=@mycontext/web-client` | `CI / Test and build` |
| MCP gateway | `cd services/mcp-gateway && swift test --enable-swift-testing --disable-xctest --no-parallel -Xswiftc -warnings-as-errors` | `CI / Test and build` |
| MCP gateway release build | `cd services/mcp-gateway && swift build -c release --product App -Xswiftc -warnings-as-errors` | `CI / Test and build` |
| Railway config | `jq empty railway/gateway.json railway/web.json` | `CI / Test and build` |
| Development deployment | `bash scripts/railway-deploy-development.sh dev all "$(git rev-parse HEAD)"` | Automatic Railway deploy after CI on `dev` |
| Production deployment | `bash scripts/railway-deploy-production.sh main all "$(git rev-parse HEAD)"` | Protected manual Railway deploy after CI on `main` |

CI uses `scripts/ci-detect-changes.sh` for path detection and `scripts/ci.sh` as the shared local/GitHub entrypoint.
