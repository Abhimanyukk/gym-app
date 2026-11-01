#!/bin/sh
# Run once as root, with PostgreSQL running. No password enters process arguments.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo." >&2; exit 1; }
directory=${1:-/etc/replab}
export REPLAB_OWNER_PASSWORD REPLAB_APP_PASSWORD
REPLAB_OWNER_PASSWORD=$(sed -n 's/^POSTGRES_PASSWORD=//p' "$directory/owner.env")
REPLAB_APP_PASSWORD=$(sed -n 's/^POSTGRES_PASSWORD=//p' "$directory/runtime.env")
[ -n "$REPLAB_OWNER_PASSWORD" ] && [ -n "$REPLAB_APP_PASSWORD" ] || { echo "Generate configuration first." >&2; exit 1; }
existing=$(runuser -u postgres -- psql -X -At -v ON_ERROR_STOP=1 -d postgres -c \
    "SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname IN ('replab_owner','replab_app')) OR EXISTS(SELECT 1 FROM pg_database WHERE datname='replab')")
[ "$existing" = f ] || { echo "RepLab database/roles already exist; refusing to overwrite or rotate them." >&2; exit 1; }
runuser -u postgres -- psql -X -v ON_ERROR_STOP=1 -d postgres <<'SQL'
\getenv owner_password REPLAB_OWNER_PASSWORD
\getenv app_password REPLAB_APP_PASSWORD
SELECT format('CREATE ROLE replab_owner LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L', :'owner_password') \gexec
SELECT format('CREATE ROLE replab_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L', :'app_password') \gexec
CREATE DATABASE replab OWNER replab_owner;
REVOKE CONNECT,TEMP ON DATABASE replab FROM PUBLIC;
GRANT CONNECT ON DATABASE replab TO replab_app;
SQL
echo "Created database and restricted roles. Next run the executable's migrate command."
