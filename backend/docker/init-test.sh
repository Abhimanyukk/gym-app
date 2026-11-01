#!/bin/sh
set -eu
psql -X -v ON_ERROR_STOP=1 --username postgres --dbname replab_test <<'SQL'
\getenv owner_password OWNER_DB_PASSWORD
\getenv app_password APP_DB_PASSWORD
SELECT format('CREATE ROLE replab_owner LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L', :'owner_password') \gexec
SELECT format('CREATE ROLE replab_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L', :'app_password') \gexec
ALTER DATABASE replab_test OWNER TO replab_owner;
SQL
