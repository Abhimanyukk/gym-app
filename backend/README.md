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

## Implemented scope

- Axum/Tokio API; SQLx PostgreSQL pool capped at five connections.
- Admin login/logout, eight-hour opaque bearer sessions, current-admin lookup,
  password changes that verify the current password and revoke all own sessions.
- Argon2id passwords (64 MiB, three iterations, parallelism four), NFC password
  normalization, 15–128-character new passwords. Hashes run outside async workers,
  with at most two concurrent hashes. No default credentials or public bootstrap.
- Maximum three admins, normalized unique emails, transaction lock + DB constraints.
- Persistent login limits: 10/email and 30/source IP per 15 minutes. Forwarded
  IP headers are ignored. Do not add an unconfigured reverse proxy.
- Gym settings; member registration, directory/search/pagination, basic profiles.
- Atomic mutation + audit + commit **before** success response; restricted DB
  runtime role; credentials/inputs/SQL not included in request logs.
- HTTPS, 16-KiB JSON body limit, 32 concurrent requests, request IDs, health checks.
- Explicit non-destructive migrations and native backup/restore-check scripts.

Not implemented: Flutter API integration, attendance/terminal ingestion, member
editing/deactivation, staff roles, subscriptions, payments, invoices, expenses,
reports, automatic backup scheduling, or forgotten-password recovery.
Unsupported dashboard totals are null, not fake zeroes. An active member record
does not imply a valid subscription or entry rights.

The tablet still uses its disconnected/preview flows. Device PIN/biometrics do
not authenticate an administrator to this server.

## 1. Prepare the Pi

Use Raspberry Pi OS Lite **64-bit** with SSH, your own user, reliable power and
NTP. Reserve its private LAN IP in your router. Ethernet is preferable.

```sh
uname -m                  # aarch64
cat /etc/os-release
hostname -I
timedatectl status
df -h /
sudo apt update
sudo apt install -y postgresql-17 postgresql-client-17 openssl ca-certificates curl
sudo systemctl enable --now postgresql
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

After a build here, `build/replab-linux-arm64.tar.gz` contains:

- `replab-server`
- `deploy/replab.service`
- native scripts under `tools/`
- this deployment guide

There are **no application source files, credentials, certificates, database
files, or sample member records** in the package. A SHA-256 sidecar is supplied.

From Windows PowerShell in `backend/`, replace the SSH user/IP:

```powershell
scp build/replab-linux-arm64.tar.gz build/replab-linux-arm64.tar.gz.sha256 YOUR_PI_USER@YOUR_PI_IP:~/
```

On the Pi:

```sh
cd ~
# The sidecar's recorded path may include build/; compare the digest explicitly:
sha256sum replab-linux-arm64.tar.gz
cat replab-linux-arm64.tar.gz.sha256
mkdir -p ~/replab-release
tar -xzf replab-linux-arm64.tar.gz -C ~/replab-release
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
sh tools/package.sh target/release/replab-server build/replab-linux-arm64.tar.gz
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

# Replace 192.168.1.50 with the Pi's reserved LAN address:
sudo /opt/replab/replab-server configure --directory /etc/replab --bind-ip 192.168.1.50
sudo chown root:replab /etc/replab/runtime.env
sudo chmod 640 /etc/replab/runtime.env
# owner.env stays root-only (0600), never loaded by the API service.
sudo sh /opt/replab/tools/create-cert.sh 192.168.1.50
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

The admin CLI securely prompts for name/email/password and works only before
any admin exists. Subsequent administrators require authenticated API calls.
No recovery/reset command is provided yet.

## 4. Start the systemd service

```sh
sudo install -m 644 deploy/replab.service /etc/systemd/system/replab.service
sudo systemctl daemon-reload
sudo systemctl enable --now replab
sudo systemctl status replab --no-pager
sudo journalctl -u replab -n 50 --no-pager
curl --cacert /etc/replab/server.crt https://192.168.1.50:8443/health/ready
```

Expected readiness: `{"status":"ready","database":"ok","schema":"1"}`.
The service starts after boot, restarts failures, runs as non-root `replab`,
and has a read-only application filesystem and 512-MiB memory cap.
Migrations are manual operator actions, never automatic API startup resets.
If PostgreSQL is down, startup fails safely and systemd retries; an unmigrated
database never reports ready.

The API is `https://<PI_IP>:8443`; `/docs` is a self-contained **static API
reference**, not Swagger or an interactive OpenAPI UI.

Clients must trust/pin the public `server.crt`; never disable certificate
validation. The self-signed certificate is valid for one year and includes the
chosen IP; plan renewal and client trust updates before expiry.
Restrict port 8443 to trusted LAN clients in the Pi/network firewall; do not
forward it publicly. Native tablet clients need no CORS setting. Browser
integration needs exact trusted origins in `CORS_ORIGINS`, never `*`.

## API contract

All `/api/v1` routes except login require `Authorization: Bearer <access_token>`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health/live`, `/health/ready` | Process and DB/schema health |
| POST | `/api/v1/auth/login` | Email/password login |
| GET | `/api/v1/auth/me` | Current admin |
| POST | `/api/v1/auth/logout` | Revoke current session |
| POST | `/api/v1/auth/change-password` | Verify current password, revoke all own sessions |
| GET, POST | `/api/v1/admins` | List/add admins, maximum three |
| GET, PUT | `/api/v1/settings` | Read/replace gym preferences |
| GET, POST | `/api/v1/members` | Searchable directory/registration |
| GET | `/api/v1/members/{uuid}` | Basic member profile |
| GET | `/api/v1/dashboard/summary` | Real member counts, unavailable totals null |

Login body: `{"email":"<admin email>","password":"<password>"}`.
Result: `access_token`, `token_type`, `expires_at`, public `admin`.
Don't put credentials/tokens into URLs, command arguments, logs or shell history.

Registration body: `{"name":"Test Member","phone":"+91 9876543210"}`.
Optional fields: `email`, `address`, `emergency_phone`, `notes`, `joined`,
`is_active`. Joining date defaults to today's IST date and cannot be future.
This does not create subscriptions, payments or biometric data.

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
separately; dumps include personal data and password hashes.
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
curl.exe --cacert certs/server.crt https://localhost:8001/health/ready
```

The Rust development endpoint is now **HTTPS** on localhost:8001, not the old
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
```

Tests cover auth/session expiry/revocation, persisted throttling, concurrent
admin cap, runtime permissions, pagination/search, settings/member persistence,
secret-redacted validation, request limits, audit rollback and legacy adoption.

Cross-build on Debian Bookworm with Rust's ARM64 target and cross-GCC:

```sh
rustup target add aarch64-unknown-linux-gnu
sudo apt install gcc-aarch64-linux-gnu
CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
  cargo build --locked --release --target aarch64-unknown-linux-gnu
sh tools/package.sh target/aarch64-unknown-linux-gnu/release/replab-server build/replab-linux-arm64.tar.gz
```

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
