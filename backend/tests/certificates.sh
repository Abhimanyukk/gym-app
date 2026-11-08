#!/bin/sh
# Run inside the disposable Rust build container as root, with a replab group.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d /tmp/replab-cert-test.XXXXXXXX)
trap 'rm -rf -- "$scratch"' EXIT
trap 'exit 1' HUP INT TERM
script="$root/tools/create-cert.sh"

for name in '' 'https://lovin.local' 'lovin.local:8443' '*.local' \
    'a,b' '-lovin.local' 'lovin..local' '0.0.0.0' '8.8.8.8' '999.999.999.999'; do
    if sh "$script" "$name" "$scratch/invalid" >/dev/null 2>&1; then
        echo "Invalid certificate name was accepted: $name" >&2
        exit 1
    fi
done
multiline=$(printf 'lovin.local\nDNS:untrusted.example')
if sh "$script" "$multiline" "$scratch/invalid" >/dev/null 2>&1; then
    echo "Multiline certificate name was accepted." >&2
    exit 1
fi
[ ! -e "$scratch/invalid" ]

sh "$script" lovin.local "$scratch/hostname" >/dev/null 2>&1
openssl x509 -in "$scratch/hostname/server.crt" -noout -checkhost lovin.local |
    grep -q 'does match'
openssl x509 -in "$scratch/hostname/server.crt" -noout -ext subjectAltName |
    grep -q 'DNS:lovin.local'
openssl verify -CAfile "$scratch/hostname/server.crt" -verify_hostname lovin.local \
    "$scratch/hostname/server.crt" >/dev/null
before=$(sha256sum "$scratch/hostname/server.crt" "$scratch/hostname/server.key")
if sh "$script" other.local "$scratch/hostname" >/dev/null 2>&1; then
    echo "Existing certificate was overwritten." >&2
    exit 1
fi
[ "$before" = "$(sha256sum "$scratch/hostname/server.crt" "$scratch/hostname/server.key")" ]
[ "$(stat -c '%a' "$scratch/hostname/server.key")" = 640 ]
[ "$(stat -c '%a' "$scratch/hostname")" = 750 ]

sh "$script" 172.20.10.3 "$scratch/legacy-ip" >/dev/null 2>&1
openssl verify -CAfile "$scratch/legacy-ip/server.crt" -verify_ip 172.20.10.3 \
    "$scratch/legacy-ip/server.crt" >/dev/null
echo "Certificate hostname/IP validation, HTTPS identity, permissions and overwrite protection passed."
