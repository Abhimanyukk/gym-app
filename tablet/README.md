# RepLab Android tablet — Rust API integration

The app has one server administrator and uses HTTPS on hardcoded port **8443**.
Fresh installation asks for hostname/IP (four dotted IPv4 boxes or hostname),
then server password, then optional biometric enrollment. No username, email,
port input, full URL or second tablet PIN is required.

Later launches resume the securely saved session automatically. If biometrics
were enabled, fingerprint/face verification is required first; otherwise the
splash proceeds directly to the dashboard after server verification.
Host/IP and biometric preferences live in **Settings → Advanced settings**.
Changing servers requires that server's password before saving the new connection;
old session keys are never sent to a different host.

Implemented: setup, login/logout/session resumption, live dashboard member counts,
server-paginated member search/registration/detail, gym settings and password changes.
Registration includes a profile photo, initial subscription and full-payment receipt.
The existing theme, fixed sidebar, sticky headers and rotating-dumbbell loaders
are retained.

Attendance, subscription renewals/refunds, billing reports and backup status do not have API endpoints.
Their unavailable states remain explicit; live sessions never load sample records.
Attendance refresh checks server readiness but does not claim to retrieve visits.
Active/inactive member **record** filters are not subscription-status filters.
Name sorting sorts the currently loaded page(s); Load more retrieves another 50.

## Add member

Requires backend **0.4.0**, explicitly migrated to **schema 3**. An older server
can still sign in, but the wizard explains that its server must be upgraded.

1. **Basic details:** name, phone, address and emergency phone are mandatory;
   email and notes are optional.
2. **Photo:** allow camera permission and take a clear photo with the member's
   consent. The inline camera supports switching cameras and retaking. This
   stores a profile image, not a biometric template or terminal enrollment.
3. **Plan:** select Silver or Gold and Monthly/Quarterly/Half-yearly/Annual.
   Optionally choose personal training and insurance durations independently,
   from one month up to the selected plan duration. Add-ons start with the plan.
4. **Payment:** collect the **full amount** in Cash or UPI. UPI displays an
   amount-specific QR for **8943521009@yescred**, **RepLab Fitness**. Staff must
   check the cash or receiving account and explicitly confirm receipt; neither
   scanning nor a customer's screenshot proves payment. A UPI reference is optional.

| Plan | 1 month | 3 months | 6 months | 12 months |
|---|---:|---:|---:|---:|
| Silver — Strength & Fitness | ₹1,200 | ₹3,200 | ₹6,000 | ₹12,000 |
| Gold — Silver + Cardio Access | ₹1,700 | ₹4,700 | ₹9,000 | ₹18,000 |

Personal training costs ₹5,000/month; insurance costs ₹200/month. Insurance
selection records the add-on purchase only; it does not issue an insurance policy.
Prices use integer paise, with totals validated by the server. A calendar-month
subscription ends on the clamped monthly anniversary **minus one day**, inclusive.
For example, 2 November–1 December is one month; 31 January–27 February 2026
is one month.

Nothing is posted until **Complete registration**. The member, normalized photo,
subscription, receipt and audit entry commit together. After an uncertain
response, use **Check registration** or **Retry same registration** without
collecting payment again. The retry retains the exact payload and ID while the
dialog stays open; after an app restart, check the directory before registering
again. Profiles show the saved photo, plan dates, add-on durations and receipt.
Legacy members honestly show no registered plan/payment instead of invented data.

The camera requests no microphone access. Native camera permission and UPI scans
still need checking on the actual tablet/phone. Browser camera preview works on
localhost when camera access is granted. Debug sample mode has no real payment
QR and never sends registrations to the server.

## Local browser integration

From the workspace root:

```powershell
docker compose -f backend/compose.yaml up -d api
docker compose -f backend/compose.yaml exec api replab-server create-admin
docker compose -f compose.preview.yaml up -d --force-recreate
```

`create-admin` securely prompts for password and confirmation only. It works
before an admin exists. Never use a sample/default account or expose bootstrap
over HTTP. Existing admins sign in normally; do not reset the database.

Trust the **public** `backend/certs/server.crt` in your browser/Windows user trust
store, after verifying its fingerprint with the server operator. Do not disable
TLS verification. Open `https://localhost:8443/health/ready` to confirm certificate
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
2. Prefer a stable Pi hostname such as **`lovin.local`**, with a certificate
   covering that exact hostname. Backend 0.4.1 listens on all IPv4 interfaces;
   future DHCP/Wi-Fi changes do not require changing a hostname certificate.
   See the backend README's one-time hostname/certificate setup. Verify `.local`
   resolution on the actual tablet/network; use managed local DNS if mDNS is
   unsupported or blocked. An IP-only certificate still needs updating if its IP changes.
3. Copy only its public certificate to `assets/certificates/server.crt`.
   Use the certificate specified by `TLS_CERT_PATH`: fresh installations use
   `/etc/replab/server.crt`; the hostname upgrade uses
   `/etc/replab/hostname-v0.4.1/server.crt`. Substitute the appropriate path below;
   do not accidentally copy the retained, old IP-only certificate.
   The protected `/etc/replab` directory cannot be read directly by the ordinary
   SSH user. On the Pi (substitute your SSH user's home if it is not `pi`):

   ```sh
   sudo install -m 644 /etc/replab/server.crt /home/pi/replab-server.crt
   sudo openssl x509 -in /etc/replab/server.crt -noout -fingerprint -sha256
   ```

   From PowerShell at the workspace root, substitute the actual Pi IP:

   ```powershell
   scp pi@192.168.1.50:/home/pi/replab-server.crt .\tablet\assets\certificates\server.crt
   docker exec gym-app-build openssl x509 -in /workspace/tablet/assets/certificates/server.crt -noout -fingerprint -sha256
   ```

   Verify that the SHA-256 certificate fingerprints match before trusting or
   bundling it. Never copy `server.key`, environment files, DB passwords or
   member records.
4. Build inside the existing Flutter container; substitute the stable Pi hostname:

```powershell
docker exec -w /workspace/tablet gym-app-build flutter pub get
docker exec -w /workspace/tablet gym-app-build flutter build apk --release --dart-define=API_BASE_URL=https://lovin.local:8443
```

APK: `build/app/outputs/flutter-apk/app-release.apk`.
Only the hostname from `API_BASE_URL` pre-fills first setup; its port cannot
override the hardcoded 8443. Without that define, enter the hostname/IP.
Once saved, device settings take precedence over build defaults. Android loads
`assets/certificates/server.crt` by default, in addition to standard trusted
certificate authorities; no certificate build flag is needed. `API_CERT_ASSET`
can explicitly select a different asset (or an empty value for standard roots
only). Custom certificate trust still validates the certificate chain, hostname/IP and
expiry; it never installs an accept-all certificate callback.

Rebuild with the Pi's public certificate before deploying an APK built with the
Windows development server certificate. Changing the host in Advanced settings
does not change certificate trust. Certificate renewal or identity changes require coordinated
client trust updates. Current APK release signing uses the existing debug
keystore; configure your own release keystore before a production rollout.

For USB development against this PC, a localhost-certificate APK can use
`https://localhost:8443` with `adb reverse tcp:8443 tcp:8443`; this does not expose
the PC API to the LAN or require opening a Windows firewall port.
ADB/device permissions and a connected tablet must still be configured.

## Browser preview against the Pi

A successful readiness check on the Pi proves the API/database are ready, not
that the PC or tablet trusts its certificate. Android certificate assets do not
configure browser trust. Also, a new Pi configuration has `CORS_ORIGINS=` empty:
browser API access is intentionally disabled until its exact origin is allowed.

1. Transfer and verify the Pi's **public** certificate as above. For Chrome/Edge
   on Windows, explicitly trust that verified certificate in your current-user
   store (subject to your organization's certificate policy):

   ```powershell
   Import-Certificate -FilePath (Resolve-Path .\tablet\assets\certificates\server.crt).Path -CertStoreLocation Cert:\CurrentUser\Root
   ```

   Restart the browser, then open `https://<PI_HOSTNAME>.local:8443/health/ready`.
   It must show ready JSON without a certificate warning. Other browsers may
   require configuring their own certificate store.
2. On the Pi, use `sudoedit /etc/replab/runtime.env` to change **only** this line
   for the preview served at `http://localhost:8080`:

   ```dotenv
   CORS_ORIGINS=http://localhost:8080
   ```

   Keep the file private; never paste its contents into a support message.
   Then run `sudo systemctl restart replab`. If the preview uses another origin,
   allow that exact scheme, hostname and port instead; never use `*`.
3. In the preview setup, enter the stable Pi hostname (`lovin.local`). To pre-fill it:

   ```powershell
   $env:API_BASE_URL = 'https://lovin.local:8443'
   docker compose -f compose.preview.yaml up -d --force-recreate
   ```

If requests still fail, inspect the browser's Network/Console panels to
distinguish certificate, CORS, local-network permission, and timeout errors.
Do not disable TLS verification or browser security. Native Android needs the
Pi certificate bundled in its APK, but does not need browser CORS permission.

## Sessions and failures

Android remembers a random, revocable 256-bit session key in encrypted
`flutter_secure_storage`, together with host and biometric preferences; it
**never stores the server password**. Android backup is disabled to avoid
restoring enrollment into a fresh installation. Member directories are not
persisted locally. Tokens are never written to logs or plain preferences.

The server stores only token hashes. Successful resume renews a 90-day idle
lifetime without rotating the key, so a lost response cannot strand the tablet.
Password is needed again only after sign-out, reinstall, password/session
revocation or expiry after inactivity. Network errors retain the stored key and
offer retry, not a fake offline dashboard. Enabled biometrics re-lock the app
when it is backgrounded. Biometrics are optional and do not replace server
verification; device PIN fallback is not an additional app login.

Browser preview saves the host only, not bearer keys in browser storage.
A browser reload therefore asks for the password again; Android does not.
Long-lived sessions use daily expiry checkpoints instead of a single 90-day
browser timer, avoiding timer overflow and immediate false expiry. Actual expiry
and server-side revocation remain enforced.
Revocation/password changes return to login and close open dialogs.
Logout forgets the saved tablet key even if server revocation cannot be
confirmed, with a warning that the old key then expires normally.

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
contract: first setup, remembered sessions with/without biometrics, member
persistence/search/details, advanced settings, revocation, offline states, and serialization.
`test/native_https_test.dart` additionally checks actual HTTPS and persistent
writes against an explicitly prepared, fresh `replab_test` database served on
`https://localhost:8443`. Its two checks are skipped by default; never point them
at the live database. Run with `LIVE_TEST_API_URL` and `API_CERT_ASSET` Dart defines
only after seeding the synthetic administrator specified in that test.
Physical tablet networking, certificate trust, Android unlock and Pi deployment
still require hardware checks.
