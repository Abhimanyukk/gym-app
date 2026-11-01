# RepLab Android tablet — Rust API integration

The app authenticates administrators over HTTPS. Android additionally requires
the tablet PIN/biometrics; unlocking the tablet alone never grants server access.
The browser skips the device-unlock step, not server authentication.

Implemented: login/logout/session expiry, live dashboard member counts,
server-paginated member search/registration/detail, gym settings, admin creation
(maximum three, enforced by the server), and password changes.
The existing theme, fixed sidebar, sticky headers and rotating-dumbbell loaders
are retained.

Attendance, subscriptions, billing and backup status do not have API endpoints.
Their unavailable states remain explicit; live sessions never load sample records.
Attendance refresh checks server readiness but does not claim to retrieve visits.
Active/inactive member **record** filters are not subscription-status filters.
Name sorting sorts the currently loaded page(s); Load more retrieves another 50.

## Local browser integration

From the workspace root:

```powershell
docker compose -f backend/compose.yaml up -d api
docker compose -f backend/compose.yaml exec api replab-server create-admin
docker compose -f compose.preview.yaml up -d --force-recreate
```

`create-admin` securely prompts for your own name/email/password. It only works
before an admin exists. Never use a sample/default account or expose bootstrap
over HTTP. Existing admins sign in normally; do not reset the database.

Trust the **public** `backend/certs/server.crt` in your browser/Windows user trust
store, after verifying its fingerprint with the server operator. Do not disable
TLS verification. Open `https://localhost:8001/health/ready` to confirm certificate
trust, then `http://localhost:8080` and sign in. The server's development CORS
allowlist includes that exact browser origin. A certificate/CORS/network failure
is shown in the login form instead of letting the user into the dashboard.

Preview now defaults to the real login. To view fictional UI fixtures instead:

```powershell
$env:SHOW_SAMPLE_DATA = 'true'
docker compose -f compose.preview.yaml up -d --force-recreate
# Restore real server login:
$env:SHOW_SAMPLE_DATA = 'false'
docker compose -f compose.preview.yaml up -d --force-recreate
```

Fixtures are available only in debug web runs. The production entry point is
`lib/main.dart`; it never bypasses server authentication.

## Raspberry Pi / Android build

1. Deploy the backend using `../backend/README.md`; create the first admin on it.
2. Reserve the Pi's private IP and ensure its certificate includes that exact IP.
3. Copy only its public `server.crt` to `assets/certificates/server.crt`.
   Never copy `server.key`, environment files, DB passwords or member records.
4. Build inside the existing Flutter container; substitute the actual Pi IP:

```powershell
docker exec -w /workspace/tablet gym-app-build flutter pub get
docker exec -w /workspace/tablet gym-app-build flutter build apk --release --dart-define=API_BASE_URL=https://192.168.1.50:8443 --dart-define=API_CERT_ASSET=assets/certificates/server.crt
```

APK: `build/app/outputs/flutter-apk/app-release.apk`.
The configured address pre-fills the login form; staff can change it when signed
out. Without `API_BASE_URL`, enter the HTTPS address manually. Without
`API_CERT_ASSET`, Android uses standard trusted certificate authorities.
Custom certificate trust still validates the certificate chain, hostname/IP and
expiry; it never installs an accept-all certificate callback.

Rebuild with the Pi's public certificate before deploying an APK built with the
Windows development server certificate. Renewal/IP changes require coordinated
client trust updates. Current APK release signing uses the existing debug
keystore; configure your own release keystore before a production rollout.

For USB development against this PC, a localhost-certificate APK can use
`https://localhost:8001` with `adb reverse tcp:8001 tcp:8001`; this does not expose
the PC API to the LAN or require opening a Windows firewall port.
ADB/device permissions and a connected tablet must still be configured.

## Sessions and failures

Bearer tokens are memory-only: restart requires login. No credentials, tokens,
or member directory are stored in preferences/local files. Server expiry,
revocation or password changes return to login and close open dialogs.
Logout clears the tablet session even if server revocation cannot be confirmed;
the UI warns that the old server session then expires normally.

Read failures preserve already-loaded data with an error/retry notice, not a
claim of successful synchronization. Search requests ignore stale responses.
Writes disable duplicate submission while pending. A timeout/5xx response may
mean a committed change: the form warns, blocks resubmission, and tells staff to
check server records first. There are no automatic mutation retries/offline writes.
Member numbering, admin limits, validations and authorization remain server rules.

## Checks

```powershell
docker exec -w /workspace/tablet gym-app-build flutter analyze --no-pub
docker exec -w /workspace/tablet gym-app-build flutter test --no-pub
```

Default tests use synthetic HTTP responses and exercise the complete UI-to-client
contract: device unlock plus server login, member persistence/search/details,
settings/admin cap, session revocation, offline states, and request serialization.
`test/native_https_test.dart` additionally checks actual HTTPS and persistent
writes against an explicitly prepared, fresh `replab_test` database served on
`https://localhost:9443`. Its two checks are skipped by default; never point them
at the live database. Run with `LIVE_TEST_API_URL` and `API_CERT_ASSET` Dart defines
only after seeding the synthetic administrator specified in that test.
Physical tablet networking, certificate trust, Android unlock and Pi deployment
still require hardware checks.
