#!/bin/sh
set -eu
: "${APP_DB_PASSWORD:?Set APP_DB_PASSWORD}"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    --set=app_password="$APP_DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE replab_app LOGIN PASSWORD %L', :'app_password') \gexec
SQL
