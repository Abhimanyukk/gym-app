# RepLab — native Rust + PostgreSQL backend

Production runs **directly on Raspberry Pi OS 64-bit**, without Docker or Python:

```text
Android tablet -> HTTPS -> replab-server (systemd) -> local PostgreSQL
```

The executable contains the API, static `/docs` reference, SQL migrations and
initial-admin/configuration commands. Deploy the executable and operator files,
not Rust source, Cargo, or the Flutter toolchain. Rust is required only to build.
The executable is Linux ARM64 and dynamically uses standard Linux system
libraries; build against an OS compatible with the Pi, not Windows.
Current release: **0.6.2**, database **schema 4**. Member directory responses now
include the saved profile photo, so the existing tablet APK displays photos
instead of initials. Records without a photo are unchanged. Reports are read-only;
upgrading from 0.5.0 requires no new schema migration.

## Simple native installation / update

Use **`build/replab-server_0.6.2-1_arm64.deb`** on Raspberry Pi OS **64-bit**
(Bookworm or newer). Copy it to the Pi, then run just:

```sh
sudo apt install ./replab-server_0.6.2-1_arm64.deb
```

The package installs required host dependencies, including PostgreSQL if needed;
no Docker, Rust compiler or application source is deployed. For your existing
Pi it keeps the administrator/password, sessions, database and TLS configuration.
The installer stops API writes, creates a **restore-verified backup**, preserves
the previous executable/private configuration, explicitly migrates to schema 4,
starts the systemd service, and checks HTTPS readiness locally. It does not need
the current Wi-Fi IP or functioning `.local` resolution for that check.

On a **fresh Pi only**, finish by choosing your server password:

```sh
sudo replab-setup
```

This is the existing secure password/confirmation prompt. There is no default
password and no public bootstrap endpoint. Repeating it on an existing installation
does not change the administrator/password.

Transfer from this workspace's `backend/` directory, using the working Pi name/IP:

```powershell
scp build/replab-server_0.6.2-1_arm64.deb pi@lovin.local:~/
```

A `.sha256` sidecar is available for independent transfer verification. Install
only a package received from your trusted build/operator.

Fresh setup uses the Pi's existing hostname plus `.local` for its certificate.
The public client certificate is exported to **`/var/lib/replab-client/server.crt`**,
readable by the ordinary SSH user. Verify its fingerprint before trusting it in
the browser or bundling it into the tablet app. Existing TLS identity is not
regenerated. There is no accept-all certificate or firewall bypass.

### Safety, retries and removal

- Native installation expects the existing generated `runtime.env`/`owner.env`,
  matching restricted roles, and local PostgreSQL at `127.0.0.1:5432`.
  Custom ports/remote databases or incomplete configuration are refused, not reset.
- Upgrade backups live in **`/var/backups/replab/install-…/`** (root-only). They
  contain the verified database dump, previous application and sensitive private
  configuration/key material. Copy them to protected off-Pi storage; the same
  memory card is not a backup against card failure. No automatic deletion/rotation.
- The package payload is staged in `/usr/lib/replab`; the running executable at
  `/opt/replab` is not replaced during package unpacking. It is activated only
  after the pre-upgrade backup/restore check succeeds.
- Failed backups leave the old executable in place. A failure after stopping
  the API leaves it stopped and retains backups; it never silently restores data
  or starts an old executable on a newer schema. Fix the reported cause and run
  `sudo dpkg --configure -a` to retry a failed package configuration.
- Package-managed service defaults are installed under `/lib/systemd/system`;
  existing `/etc/systemd/system/replab.service` overrides are preserved.
- Removing/purging the package stops/disables the API but **retains** PostgreSQL,
  `/etc/replab`, `/opt/replab`, exported public certificate and backups. Removing
  financial/member records is never an uninstall side effect.

The detailed tarball/manual procedures below remain available for advanced
operators; they are no longer required for a normal `.deb` install/update.
Update the tablet app alongside the schema-4 server before registering new members.

## Implemented scope

- Axum/Tokio API; SQLx PostgreSQL pool capped at five connections.
- Password-only login/logout, revocable opaque device sessions with a 90-day
  idle lifetime renewed by authenticated resume, and current-admin lookup.
  Password changes verify the current password and revoke every saved session.
- Argon2id passwords (64 MiB, three iterations, parallelism four), NFC password
  normalization, 15–128-character new passwords. Hashes run outside async workers,
  with at most two concurrent hashes. No default credentials or public bootstrap.
- Exactly one administrator, enforced transactionally and by DB constraints.
  Legacy account metadata is preserved but is not used for login.
- Persistent login limits: 10/server and 30/source IP per 15 minutes. Forwarded
  IP headers are ignored. Do not add an unconfigured reverse proxy.
- Gym settings; member registration, directory/search/pagination, full profiles.
- Four-step tablet enrollment: required contact/address/emergency details,
  profile photo, configurable subscription and independently timed add-ons,
  full Cash/UPI payment recorded by explicit staff confirmation.
- Settings-based plan management: names/descriptions, custom duration prices,
  archive/reactivate, monthly training/insurance rates, audited revision checks.
- Server-calculated integer-paise totals, append-only numbered registration
  receipts and idempotent retries/lookup for uncertain responses.
- Authenticated financial collections reports: today/yesterday/month/all-time,
  inclusive IST date filters, Cash/UPI and plan/add-on splits, zero-filled daily
  history, paginated receipts. These report staff-confirmed money collected,
  not earned revenue/profit; expenses/refunds/unrecorded payments are excluded.
- Atomic mutation + audit + commit **before** success response; restricted DB
  runtime role; credentials/inputs/SQL not included in request logs.
- HTTPS, 16-KiB JSON body limit (128 KiB for plans, 3 MiB for photo enrollment),
  32 concurrent requests, request IDs, health checks.
- Explicit non-destructive migrations and native backup/restore-check scripts.

Flutter API integration is implemented in `../tablet/`; see its README for
login, certificate trust and Android builds.
Not implemented: attendance/terminal ingestion, member
editing/deactivation, staff roles, subscription renewal/freeze/cancellation,
partial payments/refunds, tax invoices, payment-provider verification, expenses,
reports, automatic backup scheduling, or forgotten-password recovery.
Unsupported dashboard totals are null, not fake zeroes. An active member record
does not imply a valid subscription or entry rights.

The tablet enrolls once using the server password, then securely remembers a
random session key, never the password. Optional biometrics gate local unlock;
the key must still pass server authentication. HTTPS port **8443 is hardcoded**
in the executable and app. `API_PORT` and `API_BIND_IP` entries in old configurations
are ignored in v0.4.1. HTTPS listens on **all IPv4 interfaces (`0.0.0.0:8443`)**;
development HTTP always stays on `127.0.0.1:8443`. Only allowed hosts/origins, certificate paths and database
connection settings remain configurable.

## Upgrade an existing v0.4.1 Pi to v0.5.0

Use `build/replab-linux-arm64-v0.6.2.tar.gz` and its SHA-256 sidecar. Transfer both,
verify their digests, and extract into a **new** directory:

```sh
cd ~
sha256sum replab-linux-arm64-v0.6.2.tar.gz
cat replab-linux-arm64-v0.6.2.tar.gz.sha256
# Continue only if the digests match.
mkdir ~/replab-release-v0.5.0
tar -xzf replab-linux-arm64-v0.6.2.tar.gz -C ~/replab-release-v0.5.0
cd ~/replab-release-v0.5.0
./replab-server --version
ldd ./replab-server
```

After confirming that the new executable runs, stop writes and create a
restore-verified backup. Do not proceed if verification fails:

```sh
sudo test ! -e /opt/replab/replab-server-pre-v0.5.0
sudo systemctl stop replab
sudo sh /opt/replab/tools/backup.sh "/var/backups/replab/pre-v0.5.0-$(date +%Y%m%d-%H%M%S).dump" --verify
```

Copy that verified backup off the Pi. Then install and explicitly migrate:

```sh
sudo cp -an /opt/replab/replab-server /opt/replab/replab-server-pre-v0.5.0
sudo install -o root -g root -m 755 ./replab-server /opt/replab/replab-server
sudo cp -r tools /opt/replab/
sudo /opt/replab/replab-server --env-file /etc/replab/owner.env migrate
sudo systemctl reset-failed replab
sudo systemctl start replab
# Use the active TLS_CERT_PATH and a host already in ALLOWED_HOSTS:
sudo curl --cacert /etc/replab/hostname-v0.4.1/server.crt https://lovin.local:8443/health/ready
```

Expected readiness: `{"status":"ready","database":"ok","schema":"4"}`.
If your active certificate is elsewhere, substitute its path. This upgrade
does **not** regenerate certificates/configuration, initialize the database,
create another admin or change session keys. Keep existing environment files
and the hostname allowlist intact.

Migration 4 adds one saved catalogue seeded with the original Silver/Gold prices
and add-on rates. Existing members, photos, subscriptions and receipts are not
rewritten. **Install the updated tablet app** before new registrations: server
0.5.0 requires a catalogue revision to prevent silently accepting payment at an
outdated price. Use **Settings → Manage plans** to publish catalogue changes.

Keep the old executable and verified pre-upgrade backup. Replacing the executable
alone is **not** a rollback: 0.4.x will not report ready on schema 4. A downgrade
requires a deliberate restore of the verified schema-3 backup into a new database;
see Recovery below. Never reset the live database to solve an upgrade failure.

## Network-independent startup — v0.4.1

The server no longer binds to a DHCP address or waits for `network-online.target`.
It can start with no Wi-Fi and continue listening when Wi-Fi/Ethernet or an IPv4
address changes. PostgreSQL still stays local. An old `API_BIND_IP` value cannot
make startup fail with `Cannot assign requested address`.

Listening and identification are separate. For the tablet to keep using the same
secure address after DHCP changes, use a stable hostname such as **`lovin.local`**
(your Pi's current hostname), not a changing IP. Keep the Host allowlist, HTTPS
hostname verification, saved-session authentication and browser CORS restrictions.
Do not set `ALLOWED_HOSTS=*` or disable certificate checks.

All-interface binding includes every IPv4 network interface: expose port 8443
only to trusted local clients using the Pi/network firewall, never public router
port forwarding. This does not make an IPv6-only network supported.

### Upgrade the existing v0.4.0 Pi

Package: `build/replab-linux-arm64-v0.4.1.tar.gz` with its SHA-256 sidecar.
Transfer it using the Pi's currently reachable address (or working hostname),
verify the checksum, and extract into a new directory:

```sh
cd ~
sha256sum replab-linux-arm64-v0.4.1.tar.gz
cat replab-linux-arm64-v0.4.1.tar.gz.sha256
# Continue only if the digests match.
mkdir ~/replab-release-v0.4.1
tar -xzf replab-linux-arm64-v0.4.1.tar.gz -C ~/replab-release-v0.4.1
cd ~/replab-release-v0.4.1
./replab-server --version
ldd ./replab-server
sudo sh /opt/replab/tools/backup.sh "/var/backups/replab/pre-v0.4.1-$(date +%Y%m%d-%H%M%S).dump" --verify
```

After all checks pass:

```sh
sudo systemctl stop replab
# Refuse to replace an earlier rollback copy.
sudo test ! -e /opt/replab/replab-server-pre-v0.4.1
sudo test ! -e /etc/systemd/system/replab.service-pre-v0.4.1
sudo cp -an /opt/replab/replab-server /opt/replab/replab-server-pre-v0.4.1
sudo cp -an /etc/systemd/system/replab.service /etc/systemd/system/replab.service-pre-v0.4.1
sudo install -o root -g root -m 755 ./replab-server /opt/replab/replab-server
sudo cp -r tools /opt/replab/
sudo install -m 644 deploy/replab.service /etc/systemd/system/replab.service
sudo systemctl daemon-reload
sudo systemctl reset-failed replab
sudo systemctl start replab
sudo curl --cacert /etc/replab/server.crt https://127.0.0.1:8443/health/ready
```

The schema is still **3**: no new migration, DB initialization, admin creation or
credential reset is needed when upgrading from v0.4.0. Existing certificates
and sessions are untouched. The final local health check uses the existing
certificate's loopback SAN, independent of the Wi-Fi IP.

### One-time stable hostname / certificate setup

On the Pi:

```sh
hostname -s                 # lovin on your current Pi
sudo apt install -y avahi-daemon
sudo systemctl enable --now avahi-daemon
```

Use that hostname plus `.local`. In your existing `/etc/replab/runtime.env`,
append `lovin.local` to `ALLOWED_HOSTS`, preserving existing entries and all secrets.
An IP-only certificate does not cover a new hostname. Generate a hostname
certificate in a **new** directory, without overwriting the existing key/cert:

```sh
sudo sh /opt/replab/tools/create-cert.sh lovin.local /etc/replab/hostname-v0.4.1
sudo openssl x509 -in /etc/replab/hostname-v0.4.1/server.crt -noout -checkhost lovin.local -fingerprint -sha256
```

Keep the existing certificate directory untouched. Copy **only the new public**
`server.crt` to the tablet's `assets/certificates/server.crt`, verify its fingerprint,
and rebuild the APK yourself. Configure preview-browser trust for the same
verified public certificate. Before activating it, confirm clients are ready.
Then use `sudoedit /etc/replab/runtime.env` to change only:

```dotenv
TLS_CERT_PATH=/etc/replab/hostname-v0.4.1/server.crt
TLS_KEY_PATH=/etc/replab/hostname-v0.4.1/server.key
```

Restart RepLab, and check:

```sh
sudo systemctl restart replab
sudo curl --cacert /etc/replab/hostname-v0.4.1/server.crt https://lovin.local:8443/health/ready
```

Set the app's **Advanced settings → Server hostname** to `lovin.local` (no port).
Changing the saved host deliberately asks for the server password once; subsequent
launches resume the saved session. Future DHCP changes do not require a new
certificate or a different app host as long as the hostname resolves correctly.

`.local` uses local multicast DNS, not an internet service. The Pi and client must
be on a reachable network that permits multicast; guest isolation/hotspots can
block it. Android's built-in `.local` resolution is available from November 2021
resolver updates and must be verified on the actual tablet. If mDNS is unsupported
or blocked, configure ordinary local DNS for a stable name instead; don't bypass
HTTPS. A hostname conflict also needs resolving rather than assuming identity.

## Upgrade an existing v0.2/v0.3 Pi to v0.4 without resetting data

Use `build/replab-linux-arm64-v0.4.0.tar.gz` and its SHA-256 sidecar. Transfer both
to the Pi, compare their hashes, and extract into a **new** release directory.
Do not rerun `configure`, `init-db`, `create-admin` or `create-cert.sh`.
Keep the existing accounts, database, secrets, certificate and systemd unit.

```powershell
scp backend/build/replab-linux-arm64-v0.4.0.tar.gz backend/build/replab-linux-arm64-v0.4.0.tar.gz.sha256 pi@192.168.31.239:~/
```

On the Pi:

```sh
cd ~
sha256sum replab-linux-arm64-v0.4.0.tar.gz
cat replab-linux-arm64-v0.4.0.tar.gz.sha256
# Proceed only if the digests match.
mkdir ~/replab-release-v0.4.0
tar -xzf replab-linux-arm64-v0.4.0.tar.gz -C ~/replab-release-v0.4.0
cd ~/replab-release-v0.4.0
./replab-server --version
ldd ./replab-server
sudo sh /opt/replab/tools/backup.sh "/var/backups/replab/pre-v0.4-$(date +%Y%m%d-%H%M%S).dump" --verify
# Keep the old binary; stop if this backup path already exists.
sudo test ! -e /opt/replab/replab-server-pre-v0.4
```

If all checks succeed:

```sh
sudo systemctl stop replab
sudo cp -an /opt/replab/replab-server /opt/replab/replab-server-pre-v0.4
sudo install -o root -g root -m 755 ./replab-server /opt/replab/replab-server
sudo cp -r tools /opt/replab/
sudo /opt/replab/replab-server --env-file /etc/replab/owner.env migrate
# Restart only after migration succeeds.
sudo systemctl start replab
sudo curl --cacert /etc/replab/server.crt https://192.168.31.239:8443/health/ready
```

Readiness must contain `"schema":"3"`. Migration preserves the sole existing
administrator's ID, name, email and password hash, as well as all business data.
If more than one administrator exists, migration refuses atomically without
deleting anyone: stop and choose the account deliberately before proceeding.
The updated tablet requires this migration before using the registration wizard.
Schema 3 adds the `member_enrollments` table without fabricating subscriptions
or payments for old member records. Do not start the old executable against
schema 3 as a rollback; preserve the backup and use a deliberate restore into
a new database if necessary.
Old APK login bodies containing `email` remain accepted, but account selection
is now password-only. Existing keys retain their expiry until successfully resumed.

## 1. Prepare the Pi

Use Raspberry Pi OS Lite **64-bit** with SSH, your own user, reliable power and
NTP. Use a unique, stable hostname; Ethernet is preferable. A reserved IP is
optional for operations, not a server startup requirement.

```sh
uname -m                  # aarch64
cat /etc/os-release
hostname -I
timedatectl status
df -h /
sudo apt update
sudo apt install -y postgresql-17 postgresql-client-17 openssl ca-certificates curl avahi-daemon
sudo systemctl enable --now postgresql
sudo systemctl enable --now avahi-daemon
psql --version
pg_lsclusters
```

PostgreSQL 17 is the tested major version. If these packages are unavailable
on your OS release, use PostgreSQL's official Debian APT repository for that
release, or a supported newer Raspberry Pi OS; do not substitute an untested
major version blindly. Do not upgrade an existing PostgreSQL data directory
by changing packages alone.

Keep PostgreSQL listening on localhost only. Check the actual cluster:

```sh
sudo -u postgres psql -c 'SHOW listen_addresses;'
sudo -u postgres psql -c 'SHOW data_directory;'
```

If necessary, set `listen_addresses = 'localhost'` in that cluster's
`postgresql.conf` and restart PostgreSQL. Keep password-authenticated loopback
rules in `pg_hba.conf`; do not add LAN-wide `trust` rules or expose port 5432.

## 2. Obtain the executable-only deployment package

After a build here, `build/replab-linux-arm64-v0.6.2.tar.gz` contains:

- `replab-server`
- `deploy/replab.service`
- native scripts under `tools/`
- this deployment guide

There are **no application source files, credentials, certificates, database
files, or sample member records** in the package. A SHA-256 sidecar is supplied.

From Windows PowerShell in `backend/`, replace the SSH user/hostname (or use
the currently reachable IP just for transferring the package):

```powershell
scp build/replab-linux-arm64-v0.6.2.tar.gz build/replab-linux-arm64-v0.6.2.tar.gz.sha256 YOUR_PI_USER@YOUR_PI_HOST:~/
```

On the Pi:

```sh
cd ~
# The sidecar's recorded path may include build/; compare the digest explicitly:
sha256sum replab-linux-arm64-v0.6.2.tar.gz
cat replab-linux-arm64-v0.6.2.tar.gz.sha256
mkdir -p ~/replab-release
tar -xzf replab-linux-arm64-v0.6.2.tar.gz -C ~/replab-release
cd ~/replab-release
./replab-server --version
ldd ./replab-server
```

The native executable must launch on the actual Pi before proceeding. ARM64
cross-compilation/emulation is not physical-hardware validation.

Alternative: build on a compatible Linux ARM64 machine using Rust 1.85+
and the committed lockfile:

```sh
cargo build --locked --release
sh tools/package.sh target/release/replab-server build/replab-linux-arm64-v0.6.2.tar.gz
```

Compilers/source may be on a build machine; they are not production prerequisites.

## 3. Install executable, generate secrets, initialize PostgreSQL

For a **new installation**:

```sh
# If the account already exists, inspect/reuse it instead of recreating it.
sudo useradd --system --user-group --no-create-home --shell /usr/sbin/nologin replab
sudo install -d -o root -g root -m 755 /opt/replab
sudo install -d -o root -g replab -m 750 /etc/replab
sudo install -o root -g root -m 755 ./replab-server /opt/replab/replab-server
sudo cp -r tools /opt/replab/

# Use the Pi's stable hostname, not its current DHCP address:
sudo /opt/replab/replab-server configure --directory /etc/replab --hostname "$(hostname -s).local"
sudo chown root:replab /etc/replab/runtime.env
sudo chmod 640 /etc/replab/runtime.env
# owner.env stays root-only (0600), never loaded by the API service.
sudo sh /opt/replab/tools/create-cert.sh "$(hostname -s).local"
sudo sh /opt/replab/tools/init-db.sh
sudo /opt/replab/replab-server --env-file /etc/replab/owner.env migrate
sudo /opt/replab/replab-server --env-file /etc/replab/runtime.env create-admin
```

Configuration and certificate generation refuse overwrites. Database
initialization refuses existing RepLab roles/databases; it never resets them.
Keep both environment files and the private key protected.

`replab_owner` is the migration owner, **not a PostgreSQL superuser**.
`replab_app` has only API permissions. Backups use the host's trusted PostgreSQL
OS administrator, not an API route or credentials embedded in the executable.

The admin CLI securely prompts for a password and confirmation only, and works
only before the single admin exists. No username or email is required.
An authenticated API call cannot create a second administrator.
No recovery/reset command is provided yet.

## 4. Start the systemd service

```sh
sudo install -m 644 deploy/replab.service /etc/systemd/system/replab.service
sudo systemctl daemon-reload
sudo systemctl enable --now replab
sudo systemctl status replab --no-pager
sudo journalctl -u replab -n 50 --no-pager
sudo curl --cacert /etc/replab/server.crt "https://$(hostname -s).local:8443/health/ready"
```

Use `sudo` for this check: `/etc/replab` is restricted to root and the `replab`
group, so an ordinary login user cannot read the certificate through it.
Keep the directory, private key, and environment-file permissions unchanged.

Expected readiness: `{"status":"ready","database":"ok","schema":"4"}`.
The service starts after boot, restarts failures, runs as non-root `replab`,
and has a read-only application filesystem and 512-MiB memory cap.
Migrations are manual operator actions, never automatic API startup resets.
If PostgreSQL is down, startup fails safely and systemd retries; an unmigrated
database never reports ready.

The API is `https://<PI_HOSTNAME>.local:8443`; `/docs` is a self-contained **static API
reference**, not Swagger or an interactive OpenAPI UI.

Clients must trust/pin the public `server.crt`; never disable certificate
validation. The self-signed certificate is valid for one year and includes the
chosen hostname (legacy IP certificates are also supported); plan renewal and
client trust updates before expiry.
Restrict port 8443 to trusted LAN clients in the Pi/network firewall; do not
forward it publicly. Native tablet clients need no CORS setting. Browser
integration needs exact trusted origins in `CORS_ORIGINS`, never `*`.

## API contract

All `/api/v1` routes except login require `Authorization: Bearer <access_token>`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health/live`, `/health/ready` | Process and DB/schema health |
| POST | `/api/v1/auth/login` | Server password only |
| GET | `/api/v1/auth/me` | Current admin |
| POST | `/api/v1/auth/resume` | Authenticate remembered key, renew 90-day idle lifetime |
| POST | `/api/v1/auth/logout` | Revoke current session |
| POST | `/api/v1/auth/change-password` | Verify current password, revoke all own sessions |
| GET, POST | `/api/v1/admins` | Legacy account API; second-admin creation refused |
| GET, PUT | `/api/v1/settings` | Read/replace gym preferences |
| GET, PUT | `/api/v1/plans` | Read/edit the revisioned plan catalogue |
| GET, POST | `/api/v1/members` | Searchable directory/legacy basic registration |
| GET | `/api/v1/enrollment-options` | Plans, integer-paise prices, add-ons, UPI payee |
| POST | `/api/v1/members/enroll` | Atomic member/photo/subscription/full-payment registration |
| GET | `/api/v1/enrollments/{request_id}` | Recover a saved registration after a lost response |
| GET | `/api/v1/members/{uuid}` | Full profile, including registered photo/receipt |
| GET | `/api/v1/dashboard/summary` | Real member counts, unavailable totals null |

Login body: `{"password":"<password>"}`.
Result: `access_token`, `token_type`, `expires_at`, public `admin`.
Resume has no body; send the saved key in the Authorization header. It returns
`expires_at` and `admin` without rotating the key. The server stores only key
hashes. Logout revokes the current key; password change revokes every key.
Don't put credentials/tokens into URLs, command arguments, logs or shell history.

Legacy basic registration body: `{"name":"Test Member","phone":"+91 9876543210"}`.
Optional fields: `email`, `address`, `emergency_phone`, `notes`, `joined`,
`is_active`. Joining date defaults to today's IST date and cannot be future.
This does not create subscriptions, payments or biometric data.

### Customizable plans (v0.5)

`GET /api/v1/plans` returns all active/archived plans, the current `revision`,
monthly add-on rates, and fixed UPI payee details. `PUT /api/v1/plans` replaces
the catalogue using the last revision read:

```json
{
  "revision": 1,
  "plans": [
    {"code":"silver","name":"Silver Plan","description":"Strength & Fitness","active":true,
     "prices_paise":{"1":120000,"3":320000,"6":600000,"12":1200000}},
    {"code":"gold","name":"Gold Plan","description":"Silver + Cardio Access","active":true,
     "prices_paise":{"1":170000,"3":470000,"6":900000,"12":1800000}},
    {"code":"flex","name":"Flex Plan","description":"Custom access","active":true,
     "prices_paise":{"2":250025,"5":600000}}
  ],
  "training_monthly_paise":500000,
  "insurance_monthly_paise":20000
}
```

Existing plan codes are stable identities: include them even when archived;
removing one gives `422 plan_archive_required`. Names must be unique ignoring
case. Limit: 64 plans, 24 duration prices per plan, 1–120 months per duration.
Prices are positive integer paise up to 1,000,000,000; add-on rates may be zero.
The 128-KiB catalogue request limit applies. UPI fields are returned by GET but
cannot be changed through PUT.

Successful save increments `revision` and audits before/after values atomically.
A stale revision gives `409 plan_catalog_changed`; reload before editing again.
After an uncertain save, read the authoritative catalogue before retrying.
Catalogue updates apply to **future registrations only**: saved subscriptions
and receipts preserve their original plan/price snapshots.

### Complete enrollment (v0.5)

Read the authenticated catalogue from `/api/v1/enrollment-options` before
collecting payment. It supplies the current revision, active plans and prices.
Initial defaults are Silver prices ₹1,200/₹3,200/₹6,000/₹12,000
and Gold ₹1,700/₹4,700/₹9,000/₹18,000 for 1/3/6/12 calendar months.
Personal training initially is ₹5,000/month; insurance ₹200/month.
These are migration seeds, not permanent prices; the saved catalogue is authoritative.
UPI payee is `8943521009@yescred`, **RepLab Fitness**.

`POST /api/v1/members/enroll`:

```json
{
  "request_id": "00000000-0000-4000-8000-000000000001",
  "catalog_revision": 1,
  "member": {
    "name": "Test Member",
    "phone": "+91 9876543210",
    "address": "Synthetic address",
    "emergency_phone": "+91 9876543211"
  },
  "photo_base64": "<base64 JPEG or PNG profile photo>",
  "plan_code": "gold",
  "months": 3,
  "starts_on": "<today's IST date, YYYY-MM-DD>",
  "training_months": 1,
  "insurance_months": 2,
  "payment_method": "upi",
  "payment_reference": "optional transaction reference",
  "payment_confirmed": true
}
```

Generate a fresh UUID per registration; reuse its exact payload/ID for retries.
With the initial defaults, the server computes ₹10,100 / 1,010,000 paise for this combination. Client totals
are not accepted. Address/emergency phone, valid photo, selected plan/duration
and explicit full-payment confirmation are required. Only Cash/UPI are supported.
Plan duration must be one of that active plan's saved prices.
Add-on durations are 0 (not included) through the plan duration, independently.
Start date is today through 366 days ahead and cannot precede the joining date.
Add-ons share the plan start. End dates are inclusive: clamped calendar-month
anniversary minus one day, including for month ends/leap years.

Photos are at most 2 MiB decoded, JPEG/PNG only, at most 1024×1024 pixels;
the endpoint accepts at most 3 MiB JSON. The server strips metadata by resizing
to at most 512×512 and re-encoding JPEG. This is a consented profile photo, not
a biometric template; no attendance-terminal enrollment is performed.
Images stay in PostgreSQL `bytea`, so ordinary verified `pg_dump` backups include
them. Paginated directory results do not ship every full photo.

The transaction commits member + photo/subscription + receipt + audit together.
Receipts have unique `RL-000001`-style numbers (gaps are permitted), server UTC
receipt timestamps and the authenticated confirming administrator. Runtime
permissions cannot update/delete receipts. UPI is **staff-confirmed**, not
bank-verified: QR scans never automatically mark payment paid. Insurance add-on
records do not issue a policy; reporting/refunds are separate future work.

An identical retry returns the same member/receipt; changing an already-used ID
returns `409 enrollment_conflict`. Lookup returns the full saved member or
`404 enrollment_not_found`. On timeout, check or retry the same registration
without collecting payment again. Draft/retry state is retained only in the
open tablet dialog, not across app restarts; check records after a restart.

New registrations require `catalog_revision` from enrollment options. A missing
revision gives `409 app_update_required`; changed prices give
`409 plan_catalog_changed`; an archived/unavailable plan gives
`409 plan_unavailable`. No member or receipt is created for these failures.
Reload plans and reconcile any already collected payment before confirming again.
Identical retries of saved registrations are checked first and retain their
original response even after catalogue edits, including legacy pre-v0.5 requests.

Directory: `q` (name/phone/exact M-0001 number), `active` (record status),
`limit` (1–100, default 50), `offset` (nonnegative). Results contain `items`,
`total`, `limit`, `offset`; generated numbers are unique, not gapless.
Errors are `{"error":{"code":"...","message":"..."}}`; request IDs are returned
in `X-Request-ID`. Validation errors don't echo submitted values.

## 5. Backups and restore checks

Before using real data:

```sh
sudo sh /opt/replab/tools/backup.sh "/var/backups/replab/replab-$(date +%Y%m%d-%H%M%S).dump" --verify
# Check an existing dump without changing live data:
sudo sh /opt/replab/tools/verify-backup.sh /var/backups/replab/YOUR_BACKUP.dump
```

Dumps are binary-safe custom-format files, created privately without overwrites.
Verification restores into a random disposable DB and checks tables/version.
Only that generated scratch DB is dropped; the live database is never restored
over for a test. A failed dump is labelled partial and must not be used.
Verification requires space for a second temporary database.

Copy verified backups **off the Pi** to protected storage. The same microSD
card is not a backup against card failure. Protect `.env`/certificate material
separately; dumps include profile photos, financial records, personal data and password hashes.
Choose scheduling/retention before production (for example seven daily copies);
this version does not claim a scheduled job or automatic backup UI.

### Recovery

Keep a copy of damaged/original storage and stop `replab`. Verify the chosen
backup in a scratch DB. Restore into a **new, empty** database/cluster with
`replab_owner` and `replab_app` already created, never over the live database.
As PostgreSQL OS administrator, use:

```sh
sudo -u postgres pg_restore --dbname YOUR_NEW_EMPTY_DATABASE --no-owner --role=replab_owner --exit-on-error < YOUR_BACKUP.dump
```

Do not add `--no-privileges` to a live recovery: preserve runtime ACLs.
Remove restored `login_sessions` before exposing the recovered API so old
tokens cannot become usable again. Set the environment's `POSTGRES_DB` to
the recovered database, explicitly migrate, restart, and check real records.
This is a deliberate recovery procedure, not an automatic reset.

## 6. microSD now, SSD later

Native PostgreSQL uses its OS-managed data directory (find it with
`SHOW data_directory`); that resides on microSD when the Pi boots from microSD.
The former Compose `DATA_DIR` variable does **not** relocate a native cluster.

Leave fsync, WAL and synchronous commits enabled. Use reliable power,
high-endurance storage, clean shutdowns and off-Pi backups; watch free space.
An SSD is preferable for the live database once available.

Moving later:

1. Create and restore-verify an off-Pi backup.
2. Mount a Linux-filesystem SSD reliably and verify the mount with `findmnt`.
3. Stop `replab` and the actual PostgreSQL cluster cleanly.
4. Copy the **stopped** cluster data preserving ownership/permissions, or
   restore into a new SSD-based cluster.
5. Update that cluster's `data_directory` using the Pi's PostgreSQL tooling.
   Configure a systemd mount dependency on its cluster service so an absent
   SSD prevents startup instead of using an unintended directory on the card.
6. Restart PostgreSQL/API, verify member data and perform another restore check.

Never copy a running PostgreSQL data directory or delete WAL files to free space.

## Development and checks here

Docker is retained **only for Windows development/building/testing**, not Pi
production. The Flutter preview remains separate on localhost:8080.

In `backend/`, the existing ignored development `.env` and data volume remain
unchanged. `compose.yaml` retains the old project/data names:

```powershell
docker compose build api
docker compose up -d db
docker compose run --rm migrate
docker compose up -d api
curl.exe --cacert certs/server.crt https://localhost:8443/health/ready
```

The Rust development endpoint is now **HTTPS** on localhost:8443, not the old
HTTP Python server. Browser trust must be configured for its local certificate.
Do not use development credentials/configuration for the Pi.
Behind a corporate HTTPS proxy, optionally provide its already-trusted public
CA to the Docker builder (never disable TLS verification):

```powershell
docker build --secret id=dev_ca,src=certs/dev-root.pem --target runtime -t replab-api:rust .
```

Run tests against **only** the temporary `replab_test` database:

```sh
docker compose -f compose.test.yaml up --build --abort-on-container-exit --exit-code-from tests
```

For local Cargo workflows, start the test DB first and supply its test-only
environment shown in `compose.test.yaml`. Do not point tests at deployment
storage. The integration test refuses any DB name except `replab_test`.
Recreate the temporary test DB before repeating the integration fixture.

```sh
cargo fmt --all --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked --lib              # password/token unit check, no DB
cargo test --locked                   # requires isolated PostgreSQL fixture
cargo build --locked --release
sh tests/certificates.sh              # disposable Linux build container, root/replab group
```

Tests cover auth/session expiry/revocation, persisted throttling, concurrent
admin cap, runtime permissions, pagination/search, settings/member persistence,
secret-redacted validation, request limits, audit rollback and legacy adoption.
Configuration tests verify all-interface HTTPS and loopback-only HTTP even when
`API_BIND_IP` contains an unavailable legacy IP. Certificate checks cover DNS/IP
identities, name validation, permissions and overwrite refusal.
Enrollment checks cover catalogue/prices, required contact/photo/full-payment
validation, large-photo body limits, atomic rollback, concurrent duplicate
submissions, conflicting retries, JPEG normalization and append-only receipts.
Plan checks cover custom prices/durations, validation, authorization, concurrent
revision conflicts, audit rollback, archival, stale registration rejection,
unchanged historical receipts/retries and a populated schema-3 upgrade.

Cross-build on Debian Bookworm with Rust's ARM64 target and cross-GCC:

```sh
rustup target add aarch64-unknown-linux-gnu
sudo apt install gcc-aarch64-linux-gnu
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
  cargo build --locked --release --target aarch64-unknown-linux-gnu
sh tools/package.sh target/aarch64-unknown-linux-gnu/release/replab-server build/replab-linux-arm64-v0.6.2.tar.gz
# Preferred one-command Pi installer:
sh tools/package-deb.sh target/aarch64-unknown-linux-gnu/release/replab-server build/replab-server_0.6.2-1_arm64.deb
```

Installer lifecycle checks use actual `dpkg` unpack/configure/remove in a
disposable root container, with PostgreSQL/systemd/API mocked. The source mount
must be read-only and `REPLAB_DISPOSABLE_INSTALL_TEST=1`; never run this test on a
real Pi or development database:

```sh
python3 /source/tests/install_package_test.py
```

These checks cover fresh setup, manual-install adoption, verification before
activation, preserved credentials/receipts, retries, failed backups/migrations/
health checks, and non-destructive removal. Actual ARM64 execution, apt dependency
resolution and systemd startup on the physical Pi still need operator verification.

## Existing Python-era PostgreSQL databases

No old data, configuration or backups are deleted by this rewrite.
The explicit `migrate` command recognizes only Alembic revision `0001`,
checks the business columns and required constraint names, and adds a Rust
schema marker/grants transactionally. It does not recreate business tables,
change member IDs, renumber members, replace password hashes, or erase sessions.
Unknown revisions or unrecognized nonempty schemas are refused.
Back up and verify first. A legacy database still needs the owner's matching
credentials; generating new passwords does not rotate existing DB roles.

Don't copy PostgreSQL's raw Windows/container data folder into a native Pi
installation. Use a verified logical dump and deliberate restore.

## Maintenance

Back up and verify before updates; install the replacement executable while
the service is stopped, explicitly migrate, then restart and check readiness.
Keep the previous executable/verified backup until the update is confirmed.
Keep the OS, PostgreSQL and locked Rust dependencies maintained.
Limit journal retention through the Pi's journald configuration so logs don't
fill the card. Never print the private environment files into support logs.
Physical Pi reboot, mount behavior, client certificate trust, and attendance
terminal traffic still require actual-hardware validation.

Primary references:
`https://www.postgresql.org/download/linux/debian/`
`https://www.postgresql.org/docs/17/backup-dump.html`
`https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html`
`https://doc.rust-lang.org/cargo/commands/cargo-build.html`
