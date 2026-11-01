#!/bin/sh
# Native Pi: sudo sh tools/create-cert.sh 192.168.1.50 /etc/replab
set -eu
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo "Usage: $0 <private-IPv4> [config-directory]" >&2; exit 2; }
ip=$1
awk -v ip="$ip" 'BEGIN {
  n=split(ip,a,"."); if(n!=4)exit 1;
  for(i=1;i<=4;i++)if(a[i]!~/^[0-9]+$/ || length(a[i])>3 || a[i]+0>255)exit 1;
  if(!(a[1]==10 || (a[1]==172 && a[2]>=16 && a[2]<=31) || (a[1]==192 && a[2]==168) || a[1]==127))exit 1;
}' || { echo "Use a specific private or loopback IPv4 address." >&2; exit 2; }
directory=${2:-/etc/replab}
mkdir -p "$directory"
if [ -e "$directory/server.key" ] || [ -e "$directory/server.crt" ]; then
    echo "Certificates already exist; refusing to overwrite them." >&2; exit 1
fi
umask 077
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 365 \
    -subj "/CN=RepLab Gym Server" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1,IP:$ip" \
    -addext "basicConstraints=critical,CA:FALSE" \
    -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
    -addext "extendedKeyUsage=serverAuth" \
    -keyout "$directory/server.key" -out "$directory/server.crt"
chown root:replab "$directory/server.key"
chmod 640 "$directory/server.key"
chmod 644 "$directory/server.crt"
echo "Created HTTPS certificate. Trust only the public server.crt on clients."
