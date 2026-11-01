#!/bin/sh
# Native PostgreSQL custom-format dump. Binary-safe; never overwrite a file.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo." >&2; exit 1; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo "Usage: $0 <new.dump> [--verify]" >&2; exit 2; }
[ "$#" -eq 1 ] || [ "$2" = --verify ] || { echo "Unknown option." >&2; exit 2; }
output=$1
mkdir -p "$(dirname "$output")"
umask 077
set -C
exec 3>"$output" # Refuses existing files; no trap can delete another backup.
set +C
if ! runuser -u postgres -- pg_dump -d "${PGDATABASE:-replab}" --format=custom >&3; then
    echo "Backup FAILED; the new file may be partial. Do not use it." >&2; exit 1
fi
exec 3>&-
echo "Backup created: $output"
if [ "$#" -eq 2 ]; then
    sh "$(dirname "$0")/verify-backup.sh" "$output"
else
    echo "Not restore-verified. Run verify-backup.sh before relying on it."
fi
