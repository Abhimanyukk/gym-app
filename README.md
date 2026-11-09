# Gym Management App

Flutter tablet app and Rust backend development environment. The
Flutter app lives in `tablet/`; PostgreSQL runs as a separate Compose
service on the private Compose network.

## Raspberry Pi backend

The deployable server now lives separately in **`backend/`**. It includes
Rust/Axum, PostgreSQL, embedded SQL migrations, admin authentication, the enforced
single-admin limit, password-only enrollment, remembered sessions, gym settings,
and member registration/list/detail APIs with photos, customizable plans and payment receipts.
See **`backend/README.md`** for Raspberry Pi deployment on microSD, local testing,
HTTPS, native systemd services, backups/restore checks, and the later SSD move.
Production requires the compiled Linux ARM64 executable, not Rust/Python source
or Docker. Do not deploy this workspace's Flutter development container.
The preferred Pi installer is **`backend/build/replab-server_0.6.0-1_arm64.deb`**:
copy it to the Pi and run `sudo apt install ./replab-server_0.6.0-1_arm64.deb`.
It handles host dependencies, verified upgrade backups, migration and service
startup without resetting credentials or certificates. A fresh Pi additionally
runs `sudo replab-setup` once to choose its admin password; see the backend guide.
Backend 0.6.0 listens on all IPv4 interfaces and starts without an assigned Wi-Fi
address. Use a stable hostname (for this Pi, `lovin.local`) and a matching HTTPS
certificate so the app is not tied to changing DHCP IPs. The backend guide covers
the safe upgrade and one-time hostname/certificate setup; mDNS reachability must
be checked on the actual tablet/network.
Tablet API integration is implemented; see **`tablet/README.md`** for server
login, first-admin setup, HTTPS certificate trust and Pi-specific APK builds.
The physical attendance-terminal integration remains a separate next step.

## Start

Copy `.env.example` to `.env`, then run:

```sh
docker compose up -d --build
```

In VS Code, use **Dev Containers: Reopen in Container** to work inside
the Flutter/Rust development environment. Python is used only by the existing
Flutter-preview watcher, not by the backend.

## Flutter

Run static analysis and tests inside the dev container:

```sh
docker compose exec dev bash -lc 'cd tablet && flutter analyze && flutter test'
```

### Live browser preview (no Windows Flutter installation needed)

Run this from the project folder in Windows PowerShell:

```powershell
docker compose -f compose.preview.yaml up -d
```

Open `http://localhost:8080`. This uses the Flutter development image,
not an Android APK build, and does not need PostgreSQL or a `.env` file.
The first launch downloads web dependencies; subsequent starts reuse
the package cache.

The debug-only `tablet/lib/preview.dart` now opens real administrator login.
Trust the local API certificate and create the first admin as described in
`tablet/README.md`. Android continues to use `lib/main.dart`: first setup asks
for host/IP and server password, then optionally enables biometrics. Later
launches securely resume the session, without another password unless revoked.
HTTPS port 8443 is fixed in both the app and server.
Set `SHOW_SAMPLE_DATA=true` when
recreating the preview container to use the separate fictional UI fixtures.

The dashboard contains the greeting, a live gym-local clock (IST), four
summary cards, and recent check-ins with membership status badges. Only
the debug preview enables the clearly labelled reference sample data.
The normal app loads real member counts from the Rust API. **Reports** in the
sidebar shows actual registration collections: today/yesterday/month/all-time,
date filters, daily history, Cash/UPI and plan/add-on splits, and payment receipts.
These are staff-confirmed collections, not earned revenue/profit; expenses,
refunds and unrecorded historical payments are not included. Reports requires
backend 0.6.0 with the existing schema 4. Physical attendance remains unavailable;
authenticated sessions never invent totals or use preview records.

Pull down at the top of Dashboard, Attendance, Members, Reports, or Settings to refresh,
including empty and filtered lists. The gesture also works over headings,
search/filter controls, summary cards and page padding; the sidebar never
refreshes. The indicator appears at the same inset above every page,
not inside the Attendance or Members list card. In the browser preview, click
and drag down to try the same gesture. A deliberate pull reveals a bare dumbbell
above the moving content, without a circle or shadow. It rotates
after releasing a sufficiently long pull, disappears when the request finishes
(including errors), and the content retracts. That single indicator also covers
the pending server request; inline loaders are hidden while it is visible.
Initial loads and normal retries still show their own loader. Touches and small drags never show
the logo or refresh. The same shared loader is used during login and is the app's
loading style. Reduced-motion settings keep the dumbbell stationary and skip
retraction animation. Refresh retains the selected date, search, filters,
and temporary member registrations; Attendance's downward swipe still reopens
its overview. Debug preview refreshes briefly show the animation and rebuild
local data only. Normal-app Dashboard and Members refreshes request server data;
Settings reloads gym preferences without changing device connection or biometric
preferences. Attendance refresh checks readiness and explains that attendance endpoints
are not implemented.

Attendance opens on today's gym-local date, with member numbers,
check-in times (IST), membership-status badges, search, status filters,
latest/earliest sorting, and a date picker with a Today shortcut.
Daily summaries distinguish unique members from repeat check-ins and
flag expiring/expired memberships. Preview fixtures cover today and
yesterday and share the dashboard's recent visits and 30-member total.
The normal app shows unavailable data until integration; visits are
not presented as current occupancy. No manual attendance edits or
unverified terminal integration are added.

Attendance's title and date controls stay fixed. Swiping up or scrolling
anywhere over the check-ins card (including its heading, search, and filters)
folds the info ribbon and daily summaries away with a 280ms vertical shutter,
enlarging the check-ins card. Search, filters, and the check-in heading
remain fixed at the top of the card; only the attendance list scrolls.
Gestures over the info ribbon or the three daily summary cards do not hide them.
Swiping down or reverse-scrolling anywhere on the check-ins card reopens the
overview, even before the rows reach the top. The summary toggle also reopens it.
Narrow/large-text layouts start with the overview hidden and offer its
totals from the header. Reduced-motion settings disable the animation.

Members shows a searchable, membership-filtered directory with clickable profiles
and a four-step Add member wizard: basic details, mandatory camera photo, plan
and optional add-ons, then full Cash/UPI payment with manual staff confirmation.
Address and emergency phone are required. Plans and duration prices come from
the saved server catalogue; Silver/Gold initially support 1/3/6/12 months.
Personal training and insurance have independently selectable durations up to
the plan duration. UPI QR includes the exact total for `8943521009@yescred`
(RepLab Fitness). Scanning is not payment confirmation; staff must verify receipt.
Profiles include contact details, joining date, plan dates, notes, photo and the
saved registration receipt. Renewal/refund history is not implemented yet.
The debug preview has 178 fictional profiles matching the dashboard reference.
Validated additions are preview-only, remain when changing sidebar sections, and
disappear on refresh/hot restart. The authenticated app loads and registers real
records through the Rust API, uses server pagination/search and fetches full
profiles by UUID. The camera photo is a profile image, not attendance-terminal
biometric enrollment. Customizable plans require backend **0.5.0 / schema 4**;
see the safe Pi upgrade instructions in `backend/README.md`. Debug fixtures
disable the payment QR and simulate confirmation without collecting money.

Settings includes single-admin server authentication, password changes,
gym/contact details and honest terminal/backup availability indicators.
Advanced settings contains host/IP changes and optional biometric unlock.
**Settings → Manage plans** opens the plan editor without adding another sidebar
destination or password. Add or rename plans, edit their descriptions and
full-payment duration prices (1–120 months), archive/reactivate plans, and change
personal-training/insurance monthly rates. Edits remain a draft until **Save
changes** publishes them to PostgreSQL. Existing memberships and receipts keep
their original plan details and amounts. Conflicting or uncertain saves require
reloading the server catalogue before editing again.
The app remembers an encrypted session key, never the server password.
Preview settings reset on restart; preview password forms discard their inputs
and cannot create usable credentials or change any tablet PIN.
The authenticated app saves gym settings and changes passwords through the API.
Password changes revoke all saved sessions; the one-admin constraint is enforced
transactionally and in PostgreSQL, not just in the UI.
The Settings title stays fixed while its body scrolls beneath it,
matching the Attendance page header. A healthy connection has no status ribbon;
connection failures and preview/offline warnings use an amber warning ribbon.
Attendance's unavailable/preview ribbon uses the same warning icon and amber style.

The left sidebar is fixed and does not scroll; only the page body scrolls.
Short displays use compact 48px icon buttons so every destination stays
reachable without scrolling the navigation.

Dart files under `tablet/lib/` and files under `tablet/assets/` are
watched automatically, including edits made by external tools. After
an edit settles, Flutter hot-restarts the browser preview. Navigation
and form state reset; no APK is built. Keep the browser tab open.

View logs, restart after changing dependencies in `pubspec.yaml`, or stop:

```powershell
docker compose -f compose.preview.yaml logs -f preview
docker compose -f compose.preview.yaml restart preview
docker compose -f compose.preview.yaml stop preview
```

Check the watcher:

```powershell
docker compose -f compose.preview.yaml exec preview python3 -m unittest discover -s /workspace/tools
```

The preview port is exposed only on localhost. If port 8080 is already
used by the main dev container, stop that preview or change the host
port in `compose.preview.yaml`. To explicitly rebuild the development
image when its Dockerfile changes, add `--build` to the startup command.

#### Preview on a tablet on the same trusted Wi-Fi

Enable the optional LAN binding using the PC's Wi-Fi IPv4 address
(not its VPN, Docker/WSL, or corporate-adapter address):

```powershell
$env:PREVIEW_LAN_IP = '192.168.31.131' # Replace with your PC's current Wi-Fi IPv4 address.
docker compose -f compose.preview.yaml -f compose.preview.lan.yaml up -d
```

On the tablet, open `http://192.168.31.131:8080` with that same PC address.
Use **HTTP**, not HTTPS. Localhost remains available on the PC. The LAN
binding is limited to the specified adapter address.

If Windows Firewall blocks access, run the following in an
**Administrator PowerShell**, adjusting the address, subnet, interface,
and profile to your Wi-Fi network. This example is for a `/24` subnet
on a network Windows currently classifies as Public:

```powershell
New-NetFirewallRule -Name 'GymApp-Preview-WiFi-8080' -DisplayName 'Gym App Preview (local Wi-Fi)' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8080 -LocalAddress 192.168.31.131 -RemoteAddress 192.168.31.0/24 -InterfaceAlias 'Wi-Fi' -Profile Public
```

Do not disable the firewall or forward this development port on the
router. Use this only on trusted Wi-Fi. If the PC and tablet are on a
guest network, client isolation can prevent them communicating even
when both have internet access.

To return to localhost-only access, run the base startup command again.
To remove the optional firewall rule, use Administrator PowerShell:

```powershell
Remove-NetFirewallRule -Name 'GymApp-Preview-WiFi-8080'
```

For an interactive preview of the normal login screen in the main
development container:

```sh
docker compose exec dev bash -lc 'cd tablet && flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080'
```

Build the Android APK:

```sh
docker compose exec dev bash -lc 'cd tablet && flutter build apk --release'
```

The APK is written to
`tablet/build/app/outputs/flutter-apk/app-release.apk`. The web target is
for local preview; Android remains the deployment target.

The Android activity uses native immersive fullscreen: backgrounds fill
the display, while login and dashboard controls respect screen cutouts.
Fullscreen is restored when the app regains focus after authentication
or backgrounding. System bars can be temporarily revealed with an edge
swipe. The browser preview does not request fullscreen. Verify this on
the tablet after installing a newly built APK; Dart hot restart cannot
apply changes to the native Android activity.

## Database

PostgreSQL is available to the dev container at `db:5432`. Compose loads
the local credentials from `.env`; do not commit that file.
