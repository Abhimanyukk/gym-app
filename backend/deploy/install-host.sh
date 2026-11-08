#!/bin/sh
# Called only by the native package installer, never by API startup.
set -eu
umask 077
candidate=/usr/lib/replab/replab-server
tools=/usr/lib/replab/tools
runtime=/etc/replab/runtime.env
owner=/etc/replab/owner.env
initializing=/etc/replab/.package-initializing

fail() { echo "RepLab installation stopped: $*" >&2; exit 1; }
setting() {
    value=$(sed -n "s/^$2=//p" "$1")
    [ -n "$value" ] && [ "$(printf '%s\n' "$value" | wc -l)" -eq 1 ] ||
        fail "Missing or repeated $2 in $1. Existing configuration was not replaced."
    case "$value" in
        \"*\") value=${value#\"}; value=${value%\"} ;;
        \'*\') value=${value#\'}; value=${value%\'} ;;
    esac
    printf '%s\n' "$value"
}
local_database() {
    database=$(setting "$runtime" POSTGRES_DB)
    printf '%s' "$database" | grep -Eq '^[A-Za-z_][A-Za-z0-9_-]*$' ||
        fail "Unsupported database name; review the existing configuration."
    for config in "$runtime" "$owner"; do
        [ "$(setting "$config" POSTGRES_DB)" = "$database" ] &&
        [ "$(setting "$config" POSTGRES_HOST)" = 127.0.0.1 ] &&
        [ "$(setting "$config" POSTGRES_PORT)" = 5432 ] ||
            fail "This installer requires matching local PostgreSQL settings on port 5432."
    done
    [ "$(setting "$runtime" POSTGRES_USER)" = replab_app ] &&
    [ "$(setting "$owner" POSTGRES_USER)" = replab_owner ] ||
        fail "Keep the existing restricted RepLab database roles."
    # Use the local peer-authenticated PostgreSQL OS administrator for backups.
    export PGHOST=/var/run/postgresql PGPORT=5432 PGUSER=postgres PGDATABASE="$database"
    unset PGSERVICE PGSERVICEFILE PGPASSWORD PGOPTIONS
}
sql() { runuser -u postgres -- psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }

ready() {
    hosts=$(setting "$runtime" ALLOWED_HOSTS | tr ',' '\n')
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        for host in $hosts; do
            # Connect locally even with no Wi-Fi, but still verify the configured
            # Host allowlist, HTTPS identity, trust, expiry and database readiness.
            printf '%s' "$host" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9.-]*$' || continue
            if response=$(curl --silent --fail --noproxy '*' --connect-timeout 2 --max-time 5 \
                --cacert "$cert" --resolve "$host:8443:127.0.0.1" \
                "https://$host:8443/health/ready" 2>/dev/null); then
                printf '%s' "$response" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ready"' &&
                printf '%s' "$response" | grep -Eq '"database"[[:space:]]*:[[:space:]]*"ok"' &&
                    return 0
            fi
        done
        sleep 1
    done
    return 1
}

[ "$(id -u)" -eq 0 ] || fail "Run with sudo."
[ "$#" -eq 1 ] || fail "Expected configure or admin."
case "$1" in
    admin)
        [ -f "$runtime" ] && [ -f "$owner" ] || fail "Install the .deb package first."
        local_database
        count=$(sql "$database" 'SELECT count(*) FROM admins')
        if [ "$count" = 1 ]; then
            echo "RepLab already has its administrator. Existing password was not changed."
        elif [ "$count" = 0 ]; then
            exec /opt/replab/replab-server --env-file "$runtime" create-admin
        else
            fail "Unexpected administrator count; no accounts were changed."
        fi
        ;;
    configure)
        [ -d /run/systemd/system ] || fail "Raspberry Pi OS with systemd is required."
        "$candidate" --version
        systemctl start postgresql.service
        export PGHOST=/var/run/postgresql PGPORT=5432 PGUSER=postgres
        unset PGSERVICE PGSERVICEFILE PGPASSWORD PGOPTIONS PGDATABASE
        if [ ! -e "$runtime" ] && [ ! -e "$owner" ]; then
            existing=$(sql postgres "SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname IN ('replab_owner','replab_app')) OR EXISTS(SELECT 1 FROM pg_database WHERE datname='replab')")
            [ "$existing" = f ] || fail "A database/role already exists without its configuration. Nothing was reset."
            getent passwd replab >/dev/null ||
                adduser --system --group --no-create-home replab
            [ "$(id -u replab)" != 0 ] && getent group replab >/dev/null ||
                fail "A non-root replab account and replab group are required."
            install -d -o root -g replab -m 750 /etc/replab
            "$candidate" configure --directory /etc/replab --hostname "$(hostname -s).local"
            : > "$initializing"
        elif [ ! -f "$runtime" ] || [ ! -f "$owner" ]; then
            fail "Configuration is incomplete; no secrets were regenerated."
        fi
        [ "$(id -u replab)" != 0 ] && getent group replab >/dev/null ||
            fail "A non-root replab account and replab group are required."
        local_database
        if [ -f "$initializing" ]; then
            existing=$(sql postgres "SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname='replab')::text || '|' || (SELECT count(*) FROM pg_roles WHERE rolname IN ('replab_owner','replab_app'))::text")
            case "$existing" in
                false\|0) sh "$tools/init-db.sh" ;;
                true\|2) : ;; # Retry after initialization; never recreate roles.
                *) fail "Database initialization is incomplete; no roles/data were reset." ;;
            esac
            if [ ! -e /etc/replab/server.crt ] && [ ! -e /etc/replab/server.key ]; then
                sh "$tools/create-cert.sh" "$(hostname -s).local" /etc/replab
            fi
            chown root:replab "$runtime"
            chmod 640 "$runtime"
        fi
        cert=$(setting "$runtime" TLS_CERT_PATH)
        key=$(setting "$runtime" TLS_KEY_PATH)
        [ -f "$cert" ] && [ -f "$key" ] || fail "The configured TLS certificate/key is missing; neither was replaced."
        schema=$(sql "$database" "SELECT to_regclass('public.replab_schema') IS NOT NULL OR to_regclass('public.alembic_version') IS NOT NULL")
        [ "$schema" = t ] || [ -f "$initializing" ] ||
            fail "Existing database has no known schema marker. It was not initialized/reset."
        systemctl daemon-reload
        systemctl stop replab.service
        # From here a failed backup/migration/start keeps the API stopped. Never
        # silently restore a financial database or run an old binary on new schema.
        trap 'systemctl stop replab.service >/dev/null 2>&1 || true' EXIT
        trap 'exit 1' HUP INT TERM
        if [ "$schema" = t ]; then
            install -d -o root -g root -m 700 /var/backups/replab
            backup=$(mktemp -d /var/backups/replab/install-XXXXXXXXXX)
            cp -a /etc/replab "$backup/config"
            cp -a "$cert" "$backup/server.crt"
            cp -a "$key" "$backup/server.key"
            [ ! -d /opt/replab ] || cp -a /opt/replab "$backup/application"
            systemctl cat replab.service > "$backup/replab.service"
            echo "Preserving the previous release and private configuration in $backup"
            sh "$tools/backup.sh" "$backup/database.dump" --verify
        fi
        install -d -o root -g root -m 755 /opt/replab /opt/replab/tools
        staging=$(mktemp /opt/replab/.replab-server.XXXXXXXXXX)
        install -o root -g root -m 755 "$candidate" "$staging"
        mv -f "$staging" /opt/replab/replab-server
        for tool in backup.sh verify-backup.sh create-cert.sh init-db.sh; do
            install -o root -g root -m 755 "$tools/$tool" "/opt/replab/tools/$tool"
        done
        /opt/replab/replab-server --env-file "$owner" migrate
        systemctl enable --now avahi-daemon.service
        systemctl reset-failed replab.service
        systemctl enable --now replab.service
        ready || fail "HTTPS readiness failed. Check sudo journalctl -u replab; the service is stopped and backups retained."
        # Keep the public handoff separate from any private application data.
        install -d -o root -g root -m 755 /var/lib/replab-client
        install -o root -g root -m 644 "$cert" /var/lib/replab-client/server.crt
        rm -f "$initializing"
        count=$(sql "$database" 'SELECT count(*) FROM admins')
        [ "$count" = 0 ] || [ "$count" = 1 ] || fail "Unexpected administrator count."
        trap - EXIT HUP INT TERM
        echo "RepLab installed and HTTPS/database readiness verified on port 8443."
        echo "Public client certificate: /var/lib/replab-client/server.crt"
        if [ "$count" = 0 ]; then
            echo "First installation: run sudo replab-setup to choose the initial admin password."
        else
            echo "Existing administrator, sessions, certificates and gym records preserved."
        fi
        ;;
    *) fail "Unknown installer action." ;;
esac
