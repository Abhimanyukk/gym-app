#!/bin/sh
# Restore only into a newly generated scratch database; never the live DB.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo." >&2; exit 1; }
[ "$#" -eq 1 ] && [ -f "$1" ] || { echo "Usage: $0 <existing.dump>" >&2; exit 2; }
scratch="restore_check_$(openssl rand -hex 16)"
runuser -u postgres -- createdb "$scratch"
trap 'runuser -u postgres -- dropdb "$scratch"' EXIT
trap 'exit 1' HUP INT TERM
runuser -u postgres -- pg_restore --dbname "$scratch" --no-owner --no-privileges --exit-on-error < "$1"
runuser -u postgres -- psql -X -v ON_ERROR_STOP=1 -d "$scratch" <<'SQL'
SELECT count(*) AS admins FROM admins;
SELECT count(*) AS members FROM members;
SELECT count(*) AS settings FROM gym_settings;
DO $$
BEGIN
  IF to_regclass('public.replab_schema') IS NOT NULL THEN
    IF (SELECT array_agg(version) FROM replab_schema) IS DISTINCT FROM ARRAY[1]::smallint[]
       AND (SELECT array_agg(version) FROM replab_schema) IS DISTINCT FROM ARRAY[2]::smallint[]
       THEN RAISE EXCEPTION 'Unknown schema'; END IF;
  ELSIF to_regclass('public.alembic_version') IS NOT NULL THEN
    IF (SELECT array_agg(version_num::text) FROM alembic_version) IS DISTINCT FROM ARRAY['0001']::text[] THEN RAISE EXCEPTION 'Unknown legacy schema'; END IF;
  ELSE RAISE EXCEPTION 'No known migration marker';
  END IF;
END $$;
SQL
echo "Restore check passed; live data was not changed."
