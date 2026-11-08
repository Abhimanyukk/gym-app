#!/bin/sh
# Native Pi: sudo sh tools/create-cert.sh lovin.local /etc/replab
set -eu
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo "Usage: $0 <hostname-or-private-IPv4> [config-directory]" >&2; exit 2; }
name=$1
[ -n "$name" ] || { echo "A server hostname is required." >&2; exit 2; }
if printf '%s' "$name" | grep -Eq '^[0-9.]+$'; then
    awk -v ip="$name" 'BEGIN {
      n=split(ip,a,"."); if(n!=4)exit 1;
      for(i=1;i<=4;i++)if(a[i]!~/^[0-9]+$/ || length(a[i])>3 || a[i]+0>255)exit 1;
      if(!(a[1]==10 || (a[1]==172 && a[2]>=16 && a[2]<=31) || (a[1]==192 && a[2]==168) || a[1]==127))exit 1;
    }' || { echo "Use a specific private or loopback IPv4 address." >&2; exit 2; }
    san="IP:$name"
else
    printf '%s' "$name" | awk '{
      if(length($0)<1 || length($0)>253)exit 1;
      n=split($0,a,".");
      for(i=1;i<=n;i++)if(length(a[i])<1 || length(a[i])>63 || a[i]!~/^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$/)exit 1;
    }' || { echo "Use a hostname without a scheme, port or path." >&2; exit 2; }
    # Reject line breaks before placing user input in an OpenSSL extension.
    [ "$(printf '%s' "$name" | wc -l)" -eq 0 ] || { echo "Invalid hostname." >&2; exit 2; }
    san="DNS:$name"
fi
directory=${2:-/etc/replab}
if [ ! -d "$directory" ]; then
    install -d -o root -g replab -m 750 "$directory"
fi
if [ -e "$directory/server.key" ] || [ -e "$directory/server.crt" ]; then
    echo "Certificates already exist; refusing to overwrite them." >&2; exit 1
fi
umask 077
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 365 \
    -subj "/CN=RepLab Gym Server" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,$san" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
    -addext "extendedKeyUsage=serverAuth" \
    -keyout "$directory/server.key" -out "$directory/server.crt"
chown root:replab "$directory/server.key"
chmod 640 "$directory/server.key"
chmod 644 "$directory/server.crt"
echo "Created HTTPS certificate. Trust only the public server.crt on clients."
