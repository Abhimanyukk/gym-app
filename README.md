# Gym Management App

Flutter tablet app and FastAPI backend development environment. The
Flutter app lives in `tablet/`; PostgreSQL runs as a separate Compose
service on the private Compose network.

## Start

Copy `.env.example` to `.env`, then run:

```sh
docker compose up -d --build
```

In VS Code, use **Dev Containers: Reopen in Container** to work inside
the Flutter/Python development environment.

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

The debug-only `tablet/lib/preview.dart` opens the dashboard with the
same application theme. Android continues to use `lib/main.dart` and
requires device authentication.

The dashboard contains the greeting, a live gym-local clock (IST), four
summary cards, and recent check-ins with membership status badges. Only
the debug preview enables the clearly labelled reference sample data.
The normal app shows unavailable totals and an attendance-not-connected
message until the backend is integrated; it does not report invented
member counts or revenue.

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
and an Add member form. Profiles include contact details, joining date, plan dates,
notes, and recent sample attendance. Billing/history remains explicitly unavailable.
The debug preview has 178 fictional profiles matching the dashboard reference.
Validated additions are preview-only, remain when changing sidebar sections, and
disappear on refresh/hot restart. No real records are loaded or saved until the
backend and staff authorization are connected; registration saving is disabled
in the normal app. No biometric data, plans, or payments are created by the form.

Settings includes administrator management (maximum three, including the initial
admin), password-change forms, gym/contact details, an API address preference,
and honest terminal/backup availability indicators. Preview identities and settings
remain when navigating between sections, but reset on restart. Password forms
validate only and discard their input; they never store credentials, verify a
current password, create a usable login, or change the tablet PIN. Normal-app
mutations are disabled until staff authentication and backend integration exist.
The server must enforce authorization, unique identities, and the three-admin
limit transactionally; the preview/UI limit is not a security boundary.
The Settings title and subtitle stay fixed while its cards scroll beneath them,
matching the Attendance page header.

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
