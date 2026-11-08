#!/bin/sh
# Native Debian package: compiled release/operator files only, no source or data.
set -eu
[ "$#" -eq 2 ] || { echo "Usage: $0 <ARM64-replab-server> <new.deb>" >&2; exit 2; }
binary=$(realpath "$1")
output=$(realpath -m "$2")
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
file "$binary" | grep -qi aarch64 || { echo "Expected a Linux ARM64 executable." >&2; exit 2; }
[ ! -e "$output" ] && [ ! -e "$output.sha256" ] || { echo "Package/checksum exists; refusing to overwrite." >&2; exit 1; }
version=$(sed -n 's/^version = "\(.*\)"/\1/p' "$root/Cargo.toml")
printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
stage=$(mktemp -d /tmp/replab-deb.XXXXXXXXXX)
trap 'rm -rf "$stage"' EXIT
trap 'exit 1' HUP INT TERM
# mktemp's private directory must not become the payload's filesystem-root mode.
chmod 755 "$stage"
install -d "$stage/DEBIAN" "$stage/usr/lib/replab/tools" "$stage/usr/sbin" \
    "$stage/lib/systemd/system" "$stage/usr/share/doc/replab-server"
install -m 755 "$binary" "$stage/usr/lib/replab/replab-server"
install -m 755 "$root/deploy/install-host.sh" "$stage/usr/lib/replab/install-host.sh"
for tool in backup.sh verify-backup.sh create-cert.sh init-db.sh; do
    install -m 755 "$root/tools/$tool" "$stage/usr/lib/replab/tools/$tool"
done
install -m 644 "$root/deploy/replab.service" "$stage/lib/systemd/system/replab.service"
install -m 644 "$root/README.md" "$stage/usr/share/doc/replab-server/README.md"
cat > "$stage/usr/sbin/replab-setup" <<'SH'
#!/bin/sh
set -eu
exec sh /usr/lib/replab/install-host.sh admin
SH
cat > "$stage/DEBIAN/postinst" <<'SH'
#!/bin/sh
set -eu
if [ "$1" = configure ]; then
    sh /usr/lib/replab/install-host.sh configure
fi
SH
cat > "$stage/DEBIAN/prerm" <<'SH'
#!/bin/sh
set -eu
case "$1" in
    remove|deconfigure)
        systemctl disable --now replab.service
        ;;
esac
SH
cat > "$stage/DEBIAN/postrm" <<'SH'
#!/bin/sh
set -eu
case "$1" in
    remove|purge)
        if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
            systemctl daemon-reload
        fi
        echo "RepLab stopped. Database, /etc/replab, /opt/replab and backups intentionally retained."
        ;;
esac
SH
chmod 755 "$stage/usr/sbin/replab-setup" "$stage/DEBIAN/postinst" \
    "$stage/DEBIAN/prerm" "$stage/DEBIAN/postrm"
cat > "$stage/DEBIAN/control" <<EOF
Package: replab-server
Version: $version-1
Architecture: arm64
Maintainer: RepLab <admin@replab.invalid>
Section: admin
Priority: optional
Depends: libc6 (>= 2.36), libgcc-s1, postgresql-17 | postgresql-16 | postgresql-15 | postgresql (>= 15~), postgresql-client-17 | postgresql-client-16 | postgresql-client-15 | postgresql-client (>= 15~), openssl, ca-certificates, curl, adduser, util-linux, systemd-sysv, avahi-daemon
Description: RepLab native gym server and safe host installer
 Rust API, local PostgreSQL, verified upgrade backups and systemd service.
 Keeps existing credentials, TLS identity, memberships and payment receipts.
EOF
mkdir -p "$(dirname "$output")"
dpkg-deb --root-owner-group --build "$stage" "$output"
digest=$(sha256sum "$output" | cut -d ' ' -f 1)
printf '%s  %s\n' "$digest" "$(basename "$output")" > "$output.sha256"
echo "Created native Pi installer: $output"
