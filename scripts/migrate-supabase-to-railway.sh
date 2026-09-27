#!/usr/bin/env bash
# Copy MyContextProtocol's application-owned public schema from Supabase to Railway Postgres.
#
# Required:
#   SUPABASE_SOURCE_DATABASE_URL  Supabase direct/session connection URL (port 5432)
#
# Optional:
#   RAILWAY_TARGET_DATABASE_URL   Skip Railway variable discovery and use this URL
#   RAILWAY_PROJECT_ID            Railway project ID (otherwise the linked project)
#   RAILWAY_ENVIRONMENT           Defaults to dev
#   RAILWAY_POSTGRES_SERVICE      Defaults to Postgres
#   MIGRATION_ARTIFACT_DIR        Defaults to .migration-artifacts/supabase-to-railway-<environment>
#   KEEP_RAILWAY_TCP_PROXY        Set to 1 to retain a proxy created by this script
#
# Destructive target-reset guards:
#   MIGRATION_WRITERS_PAUSED=YES
#   MIGRATION_CONFIRM_TARGET_RESET='MyContextProtocol/<environment>/Postgres'
#
# Commands: preflight, export, restore, verify, migrate
set -euo pipefail

export LC_ALL=C
export PGTZ=UTC
export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-15}"

COMMAND="${1:-preflight}"
SOURCE_DATABASE_URL="${SUPABASE_SOURCE_DATABASE_URL:-}"
TARGET_DATABASE_URL="${RAILWAY_TARGET_DATABASE_URL:-}"
RAILWAY_PROJECT_ID="${RAILWAY_PROJECT_ID:-}"
RAILWAY_ENVIRONMENT="${RAILWAY_ENVIRONMENT:-dev}"
RAILWAY_POSTGRES_SERVICE="${RAILWAY_POSTGRES_SERVICE:-Postgres}"
ARTIFACT_DIR="${MIGRATION_ARTIFACT_DIR:-.migration-artifacts/supabase-to-railway-${RAILWAY_ENVIRONMENT}}"
ARCHIVE_PATH="$ARTIFACT_DIR/public-schema.dump"
SOURCE_TABLES_PATH="$ARTIFACT_DIR/source-tables.txt"
TARGET_TABLES_PATH="$ARTIFACT_DIR/target-tables.txt"
SOURCE_COUNTS_PATH="$ARTIFACT_DIR/source-counts.tsv"
TARGET_COUNTS_PATH="$ARTIFACT_DIR/target-counts.tsv"
CREATED_PROXY_ID=""

railway_scope=(--service "$RAILWAY_POSTGRES_SERVICE" --environment "$RAILWAY_ENVIRONMENT")
if [ -n "$RAILWAY_PROJECT_ID" ]; then
  railway_scope+=(--project "$RAILWAY_PROJECT_ID")
fi

fail() {
  echo "error: $*" >&2
  exit 1
}

notice() {
  echo "==> $*"
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "required tool not found: $1"
}

require_source_url() {
  [ -n "$SOURCE_DATABASE_URL" ] || fail "SUPABASE_SOURCE_DATABASE_URL is required"
  case "$SOURCE_DATABASE_URL" in
    *:6543/*) fail "use the Supabase direct or session-pooler URL on port 5432, not transaction-pooler port 6543" ;;
  esac
}

cleanup_proxy() {
  if [ -z "$CREATED_PROXY_ID" ] || [ "${KEEP_RAILWAY_TCP_PROXY:-0}" = "1" ]; then
    return
  fi
  notice "Removing temporary Railway Postgres TCP proxy"
  railway tcp-proxy delete "$CREATED_PROXY_ID" "${railway_scope[@]}" --yes --json >/dev/null \
    || echo "warning: could not remove temporary TCP proxy $CREATED_PROXY_ID" >&2
}

trap cleanup_proxy EXIT

wait_for_proxy() {
  local proxy_id="$1"
  local status_json status
  for _ in $(seq 1 30); do
    status_json="$(railway tcp-proxy status "$proxy_id" "${railway_scope[@]}" --json)"
    status="$(jq -r '.proxy.syncStatus // .syncStatus // empty' <<<"$status_json")"
    if [ "$status" = "ACTIVE" ]; then
      return
    fi
    [ "$status" != "FAILED" ] || fail "Railway TCP proxy failed to activate"
    sleep 1
  done
  fail "timed out waiting for Railway TCP proxy"
}

resolve_target_url() {
  if [ -n "$TARGET_DATABASE_URL" ]; then
    return
  fi
  require_tool railway
  require_tool jq
  local proxies proxy_id created variables
  local proxy_domain proxy_port database_name database_user database_password
  local encoded_database_name encoded_database_user encoded_database_password
  proxies="$(railway tcp-proxy list "${railway_scope[@]}" --json)"
  proxy_id="$(jq -r '.proxies[0].id // empty' <<<"$proxies")"
  if [ -z "$proxy_id" ]; then
    notice "Creating temporary Railway Postgres TCP proxy"
    created="$(railway tcp-proxy create --port 5432 "${railway_scope[@]}" --json)"
    proxy_id="$(jq -r '.proxy.id // .id // empty' <<<"$created")"
    [ -n "$proxy_id" ] || fail "Railway did not return a TCP proxy ID"
    CREATED_PROXY_ID="$proxy_id"
  fi
  wait_for_proxy "$proxy_id"
  variables="$(railway variable list "${railway_scope[@]}" --json)"
  TARGET_DATABASE_URL="$(jq -r '.DATABASE_PUBLIC_URL // empty' <<<"$variables")"
  if [ -z "$TARGET_DATABASE_URL" ]; then
    proxy_domain="$(jq -r '.RAILWAY_TCP_PROXY_DOMAIN // empty' <<<"$variables")"
    proxy_port="$(jq -r '.RAILWAY_TCP_PROXY_PORT // empty' <<<"$variables")"
    database_name="$(jq -r '.PGDATABASE // empty' <<<"$variables")"
    database_user="$(jq -r '.PGUSER // empty' <<<"$variables")"
    database_password="$(jq -r '.PGPASSWORD // empty' <<<"$variables")"
    [ -n "$proxy_domain" ] || fail "Railway did not expose the TCP proxy domain"
    [ -n "$proxy_port" ] || fail "Railway did not expose the TCP proxy port"
    [ -n "$database_name" ] || fail "Railway did not expose PGDATABASE"
    [ -n "$database_user" ] || fail "Railway did not expose PGUSER"
    [ -n "$database_password" ] || fail "Railway did not expose PGPASSWORD"
    encoded_database_name="$(jq -rn --arg value "$database_name" '$value | @uri')"
    encoded_database_user="$(jq -rn --arg value "$database_user" '$value | @uri')"
    encoded_database_password="$(jq -rn --arg value "$database_password" '$value | @uri')"
    TARGET_DATABASE_URL="postgresql://${encoded_database_user}:${encoded_database_password}@${proxy_domain}:${proxy_port}/${encoded_database_name}"
  fi
}

psql_scalar() {
  psql "$1" -X -v ON_ERROR_STOP=1 -Atqc "$2"
}

inventory_tables() {
  psql_scalar "$1" "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY table_name"
}

collect_counts() {
  local database_url="$1"
  local output_path="$2"
  psql "$database_url" -X -v ON_ERROR_STOP=1 -At -F $'\t' >"$output_path" <<'SQL'
SELECT format(
  'SELECT %L AS table_name, count(*) AS row_count FROM public.%I',
  table_name,
  table_name
)
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name
\gexec
SQL
}

check_source_scope() {
  local unexpected large_objects
  unexpected="$(psql_scalar "$SOURCE_DATABASE_URL" "
    SELECT DISTINCT table_schema
    FROM information_schema.tables
    WHERE table_type = 'BASE TABLE'
      AND table_schema NOT IN (
        'public', 'auth', 'storage', 'realtime', 'extensions', 'graphql', 'graphql_public',
        'pgbouncer', 'supabase_functions', 'supabase_migrations', 'vault',
        'analytics', '_analytics', '_realtime', 'cron', 'net', 'pgmq', 'pgsodium',
        'pgsodium_masks', 'pgtle', 'repack', 'tiger', 'tiger_data', 'topology',
        'timescaledb', 'timescaledb_information', 'information_schema', 'pg_catalog'
      )
      AND table_schema NOT LIKE 'pg_toast%'
      AND table_schema NOT LIKE 'pg_temp%'
    ORDER BY table_schema")"
  [ -z "$unexpected" ] || fail "unsupported application schema(s) outside public: $unexpected"
  large_objects="$(psql_scalar "$SOURCE_DATABASE_URL" "SELECT count(*) FROM pg_largeobject_metadata")"
  [ "$large_objects" -eq 0 ] || fail "source contains $large_objects PostgreSQL large object(s)"
}

preflight() {
  require_tool psql
  require_tool pg_dump
  require_tool pg_restore
  require_source_url
  resolve_target_url
  check_source_scope

  local source_version target_version target_tables source_size
  source_version="$(psql_scalar "$SOURCE_DATABASE_URL" 'SHOW server_version')"
  target_version="$(psql_scalar "$TARGET_DATABASE_URL" 'SHOW server_version')"
  source_size="$(psql_scalar "$SOURCE_DATABASE_URL" "SELECT pg_size_pretty(pg_database_size(current_database()))")"
  target_tables="$(inventory_tables "$TARGET_DATABASE_URL" | wc -l | tr -d ' ')"

  notice "Source Postgres: $source_version"
  notice "Target Postgres: $target_version"
  notice "Source database size: $source_size"
  notice "Source public tables: $(inventory_tables "$SOURCE_DATABASE_URL" | wc -l | tr -d ' ')"
  notice "Target public tables: $target_tables"
}

export_archive() {
  preflight
  mkdir -p "$ARTIFACT_DIR"
  notice "Exporting source public schema and data"
  pg_dump "$SOURCE_DATABASE_URL" \
    --format=custom \
    --schema=public \
    --no-owner \
    --no-privileges \
    --file="$ARCHIVE_PATH"
  inventory_tables "$SOURCE_DATABASE_URL" >"$SOURCE_TABLES_PATH"
  collect_counts "$SOURCE_DATABASE_URL" "$SOURCE_COUNTS_PATH"
  notice "Archive written to $ARCHIVE_PATH"
}

restore_archive() {
  require_tool pg_restore
  resolve_target_url
  [ -f "$ARCHIVE_PATH" ] || fail "missing archive: $ARCHIVE_PATH"
  [ "${MIGRATION_WRITERS_PAUSED:-}" = "YES" ] \
    || fail "pause the Railway Gateway, then set MIGRATION_WRITERS_PAUSED=YES"
  local expected_target="MyContextProtocol/${RAILWAY_ENVIRONMENT}/${RAILWAY_POSTGRES_SERVICE}"
  [ "${MIGRATION_CONFIRM_TARGET_RESET:-}" = "$expected_target" ] \
    || fail "set MIGRATION_CONFIRM_TARGET_RESET='$expected_target'"
  [ "$(psql_scalar "$TARGET_DATABASE_URL" 'SELECT current_database()')" = "railway" ] \
    || fail "target database identity check failed"
  notice "Resetting the disposable Railway target public schema"
  psql "$TARGET_DATABASE_URL" -X -v ON_ERROR_STOP=1 -qc 'DROP SCHEMA public CASCADE'
  if ! pg_restore --list "$ARCHIVE_PATH" | grep -Eq ' SCHEMA - public '; then
    psql "$TARGET_DATABASE_URL" -X -v ON_ERROR_STOP=1 -qc 'CREATE SCHEMA public'
  fi
  notice "Restoring the Supabase public schema and data"
  pg_restore \
    --dbname="$TARGET_DATABASE_URL" \
    --no-owner \
    --no-privileges \
    --exit-on-error \
    --jobs="${MIGRATION_RESTORE_JOBS:-1}" \
    "$ARCHIVE_PATH"
  psql "$TARGET_DATABASE_URL" -X -v ON_ERROR_STOP=1 -qc 'ANALYZE'
}

verify_copy() {
  require_source_url
  resolve_target_url
  mkdir -p "$ARTIFACT_DIR"
  inventory_tables "$SOURCE_DATABASE_URL" >"$SOURCE_TABLES_PATH"
  inventory_tables "$TARGET_DATABASE_URL" >"$TARGET_TABLES_PATH"
  diff -u "$SOURCE_TABLES_PATH" "$TARGET_TABLES_PATH" \
    || fail "source and target public table inventories differ"
  collect_counts "$SOURCE_DATABASE_URL" "$SOURCE_COUNTS_PATH"
  collect_counts "$TARGET_DATABASE_URL" "$TARGET_COUNTS_PATH"
  diff -u "$SOURCE_COUNTS_PATH" "$TARGET_COUNTS_PATH" \
    || fail "source and target row counts differ"
  notice "Verified identical public table inventories and row counts"
}

case "$COMMAND" in
  preflight) preflight ;;
  export) export_archive ;;
  restore) restore_archive ;;
  verify) verify_copy ;;
  migrate) export_archive; restore_archive; verify_copy ;;
  *) fail "usage: $0 preflight|export|restore|verify|migrate" ;;
esac
