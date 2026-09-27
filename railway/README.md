# Railway deployment

Railway hosts both active environments. Development cut over on 2026-08-09, and production cut over
on 2026-08-10. Each environment has its own Web, Gateway, and Postgres instances.

| Service | Config-as-code file | Development branch | Production branch |
| --- | --- | --- | --- |
| Gateway | `/railway/gateway.json` | `dev` | `main` |
| Web | `/railway/web.json` | `dev` | `main` |
| Postgres | Railway-managed Postgres | n/a | n/a |

Keep each repository-backed service root directory at `/`. The Gateway Dockerfile is intentionally
located at the repository root because Railway builds it from the monorepo root. Set Gateway
database fields to the corresponding `${{Postgres.PG*}}` reference variables so runtime traffic
stays on Railway's private network. The current URL-based Vapor driver path enables TLS and rejects
Railway's internal certificate, so use these existing discrete fields instead:

```text
DATABASE_HOST=${{Postgres.PGHOST}}
DATABASE_PORT=${{Postgres.PGPORT}}
DATABASE_USERNAME=${{Postgres.PGUSER}}
DATABASE_PASSWORD=${{Postgres.PGPASSWORD}}
DATABASE_NAME=${{Postgres.PGDATABASE}}
```

Do not also set `DATABASE_URL` or `SUPABASE_DB_URL`; those take precedence in `configure.swift`.

Set Web's server-only `BACKEND_URL` to `http://gateway.railway.internal:8080` in each environment.
Keep `NEXT_PUBLIC_API_URL` on the public API origin because browser requests cannot use Railway's
private network.

GitHub Actions deploys the exact tested `dev` SHA to Development after pushes to `dev`. Production
deploys are manual workflow dispatches from `main`, run through the protected `production` GitHub
environment, and require its production-scoped Railway token. The scripts fail closed unless HEAD,
the GitHub event SHA, and the current remote branch tip all match. Gateway deploys before Web.

Store the Development token as `RAILWAY_DEVELOPMENT_TOKEN` and the Production token as
`RAILWAY_PRODUCTION_TOKEN`. Keep each token scoped to this project and its corresponding
environment. Do not share database references, tokens, or public-origin variables between
environments.

Railway terminates TLS for the product wildcard and tenant custom domains. The Gateway provisions
tenant domains through Railway's API when `RAILWAY_PROJECT_TOKEN` is set on the Gateway service;
that token must be scoped to this project and the Gateway's own environment. See the development
and production runbooks under `docs/runbooks/` for guarded database-copy and DNS procedures.

## Tenant custom-domain TLS

For each environment, set a project token as the Gateway runtime secret `RAILWAY_PROJECT_TOKEN`.
The GitHub Actions deployment secrets above do **not** configure this runtime secret. Never reuse
the Production token in Development. The Gateway sends project tokens using Railway's
`Project-Access-Token` header; account/workspace `RAILWAY_API_TOKEN` bearer authentication is
supported, but prefer the narrower project/environment-scoped token.

Railway injects `RAILWAY_PROJECT_ID`, `RAILWAY_ENVIRONMENT_ID`, and `RAILWAY_SERVICE_ID`. Normally
these need no overrides. `RAILWAY_DOMAIN_PROJECT_ID`, `RAILWAY_DOMAIN_ENVIRONMENT_ID`, and
`RAILWAY_DOMAIN_SERVICE_ID` override them when explicitly configured; they must still target the
correct Gateway, not Web. Set `RAILWAY_DOMAIN_TARGET_PORT=8080` to match the Gateway listener.

The setup flow is:

1. Save the hostname in project settings. The Gateway finds or creates its Railway custom domain.
2. Add the project `_mcp-verify.<hostname>` TXT record and every Railway DNS record shown in the
   dashboard, including Railway's ownership TXT and routing CNAME. Do not reuse Fly A/AAAA targets
   or Fly ownership records as Railway requirements. Root domains require a DNS provider that
   supports CNAME flattening, ALIAS, or ANAME; Railway does not provide static routing IPs.
3. Refresh DNS and TLS checks. Project verification requires the project TXT token plus Railway
   ownership and routing readiness. Certificate issuance may remain pending afterward.
4. Verify certificate issuance and the actual custom-host HTTPS/MCP flow, not just a healthy
   Gateway deployment. A previously verified project does not prove its current Railway DNS state.

Missing runtime credentials appear as `certificate_status=not_configured`; Production hostname
saves and verification fail closed. Existing manually provisioned Railway domains can continue
serving TLS even while this secret is missing, so their health does not prove self-service works.
For a saved hostname missing from Railway, use Refresh Checks to provision it after credentials
are configured. Do not delete and recreate a domain whose certificate is already issuing.

Validate the workflow in Development first. Production secret changes and deployment require
explicit approval. Reference: [Railway domain API](https://docs.railway.com/integrations/api/manage-domains)
and [API authentication](https://docs.railway.com/integrations/api).
