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

The initial deployments were uploaded with `railway up`. GitHub Actions deploys production from
`main` with a production-scoped Railway project token stored as `RAILWAY_TOKEN`. Do not share
database references or public-origin variables between environments.

Railway terminates TLS for the product wildcard and tenant custom domains. The Gateway provisions
tenant domains through Railway's API when `RAILWAY_PROJECT_TOKEN` is set on the Gateway service;
that token must be scoped to this project and production environment. See the development and
production runbooks under `docs/runbooks/` for guarded database-copy and DNS procedures.
