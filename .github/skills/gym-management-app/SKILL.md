---
name: gym-management-app
description: "Build, extend, debug, and review the single-location gym management system using Flutter on an Android tablet, Rust/Axum on Raspberry Pi 5, PostgreSQL, and an eSSL AiFace-Mars attendance terminal. Use for architecture, implementation, database, UI, API, device integration, testing, security, and deployment tasks."
---

# Gym Management App Skill

## Project objective

Build a reliable gym administration system for one gym location. The
primary client is an Android tablet used by gym staff to manage members,
memberships, payments, attendance, expenses, and reports. The backend
and database run locally on a Raspberry Pi 5 (8 GB). An external HDD is
used for backups.

Prioritise data integrity, security, operational reliability, simple
front-desk workflows, and maintainable code.

## Fixed technology stack

Use these choices unless the user explicitly approves a change:

- Android tablet app: Flutter and Dart, developed in VS Code.
- Native Android integration: Kotlin only when a required Android API
  or SDK cannot be accessed adequately from Flutter. Use
  MethodChannel/EventChannel or Pigeon.
- Backend: Rust and Axum (user-approved replacement of Python/FastAPI).
- Database: PostgreSQL.
- Database access/migrations: SQLx, parameterized SQL, embedded explicit SQL migrations.
- Deployment: Raspberry Pi OS 64-bit; native executable and systemd in production.
  Docker is for local development/building/testing only.
- Attendance terminal: eSSL AiFace-Mars communicating over the local
  network using its configured ADMS/PUSH protocol.
- Tablet-to-server communication: authenticated REST API over the gym
  LAN.

Do not require Android Studio as the primary IDE. Android builds still
require Android SDK platform/build tools, a compatible JDK, and Gradle.
Provide VS Code and CLI workflows.

Do not introduce Firebase, Supabase, cloud hosting, another database, or
another backend without a concrete requirement and user approval.

## Architecture

Keep three components separate:

1.  Flutter tablet app: UI, navigation, form validation, and REST API
    client. It must not connect directly to PostgreSQL or implement the
    eSSL ADMS listener.
2.  Rust/Axum on Raspberry Pi: authentication, authorization, business
    rules, REST endpoints, terminal event receiver, and transaction
    handling.
3.  PostgreSQL: persistent storage. Do not expose it directly to the
    tablet or public internet.

Attendance flow:

`eSSL AiFace-Mars -> LAN/ADMS PUSH -> Rust receiver -> event validation/member mapping -> PostgreSQL`

Application flow:

`Flutter tablet -> authenticated REST API -> Rust/Axum -> PostgreSQL`

The terminal sends events to the Raspberry Pi. Do not make the tablet
act as the terminal server.

## eSSL AiFace-Mars integration

Treat the exact ADMS protocol and firmware behaviour as unverified until
tested on the physical terminal.

- Begin with a receive-and-log proof of concept only.
- Verify actual request paths, HTTP methods, headers, payload format,
  serial number, event fields, acknowledgement requirements, retries,
  and reconnect behaviour.
- Paths such as `/iclock/cdata`, `/iclock/getrequest`, and
  `/iclock/devicecmd` are investigation leads, not guaranteed
  specifications.
- Do not treat third-party protocol notes as authoritative.
- Preserve raw requests during initial integration for diagnostics.
- Parse defensively. Handle malformed, partial, duplicate, delayed,
  and out-of-order events.
- Acknowledge successful ingestion only after persistence has
  committed, where the protocol permits.
- Do not implement remote enrollment, template download, deletion, or
  device commands until the exact firmware protocol is verified and
  the user requests the feature.
- Assume face enrollment is performed directly on the terminal unless
  a supported API is verified.
- A successful face match does not prove that a membership is active.
  If the terminal only reports recognition, record the event and flag
  unknown, expired, frozen, or cancelled memberships. Never claim the
  backend can physically deny entry unless an access-control
  decision/relay workflow is verified.
- Avoid storing face images or biometric templates unless strictly
  necessary and explicitly approved after privacy/legal review. Prefer
  mapping the terminal's user ID to an internal member ID.

## Functional scope

### Members

Create, view, update, search, and deactivate members. Store a unique
member number, name, phone, join date, and status. Provide a profile
with subscription, payment, and attendance history. Keep terminal user
IDs in a separate mapping.

### Plans and subscriptions

Support configurable plans, prices, durations, new subscriptions,
renewals, freezes, cancellations, and expiry. Preserve subscription
history. Define whether the subscription end date is inclusive and test
the boundary.

### Payments and billing

Support cash, UPI, and card as recorded payment methods. Confirm whether
partial payments are required for each billing feature; do not assume a
policy. Generate unique invoice numbers. Record refunds as separate
transactions; never delete the original payment. Store payment
references only---never card numbers, CVVs, UPI PINs, or banking
credentials. Define revenue-reporting rules when implementing reports;
do not treat cash collected as revenue earned by default. Prepaid annual
membership is not automatically one month's earned revenue.

### Attendance

Store raw device events and normalized attendance records. Map terminal
user IDs to members. Validate subscription status at the event
timestamp. Flag unknown users, expired/frozen/cancelled subscriptions,
and duplicates. Preserve invalid attempts for audit rather than silently
discarding them. Use a stable device event ID when available; otherwise
define and document a deterministic deduplication key. Derive visit
sessions only after event semantics are understood.

### Expenses and reports

Record expense date, category, amount, payment method, and notes.
Support attendance, member, subscription-expiry, dues, collections,
refunds, expenses, and revenue reports. Provide date filters and CSV/PDF
export when requested. Label report definitions and date ranges clearly.

### Users and audit

Provide admin/staff roles and least-privilege permissions. Enforce
authorization on the backend. Audit sensitive operations, including
payment corrections, refunds, subscription changes, and role changes.

## Suggested data model

Use UUID primary keys unless the existing codebase has a justified
convention. Use foreign keys, indexes, constraints, and NUMERIC/DECIMAL
for currency---never floating-point currency types.

Suggested tables:

- `members`
- `membership_plans`
- `subscriptions`
- `devices`
- `member_devices`
- `attendance_events`
- `attendance_sessions` (optional derived records)
- `invoices`
- `payments`
- `refunds`
- `expenses`
- `staff_users`
- `roles` (or equivalent)
- `audit_logs`
- `backup_history`
- `app_settings`

Persist timestamps in UTC. Display gym-local times using `Asia/Kolkata`.
Make business-date calculations explicit. Never erase financial history
to correct an error; use refunds, reversals, adjustments, and
audit-tracked corrections.

## API conventions

Use versioned resource-oriented REST endpoints. Keep business logic in
service/domain modules, not route handlers. Use Serde input/output types,
server-side validation, pagination, and consistent error responses.

Candidate endpoints (do not create all of them without a feature
requirement):

- `POST /api/v1/auth/login`
- `GET /api/v1/dashboard/summary`
- `GET/POST /api/v1/members`
- `GET/PATCH /api/v1/members/{member_id}`
- `POST /api/v1/members/{member_id}/subscriptions`
- `GET /api/v1/members/{member_id}/attendance`
- `GET/POST /api/v1/plans`
- `POST /api/v1/invoices`
- `POST /api/v1/invoices/{invoice_id}/payments`
- `POST /api/v1/payments/{payment_id}/refunds`
- `GET /api/v1/reports/attendance`
- `GET /api/v1/reports/revenue`
- `GET /api/v1/reports/dues`
- `GET /api/v1/reports/expiring-memberships`
- `GET /api/v1/devices`
- `GET /api/v1/backups`

Inspect existing routes before adding or renaming APIs. Do not break
existing contracts without explaining the migration.

## Flutter guidelines

- Use Flutter/Dart and Material 3.
- Design responsively for the actual Android tablet size and
  orientation; do not assume fixed dimensions.
- Build reusable widgets for forms, lists/tables, dialogs, status
  indicators, date filters, and dashboard cards.
- Keep widgets focused on presentation. Put API calls in
  repositories/services and business/state logic in an appropriate
  layer.
- Inspect the existing project before selecting or changing
  state-management libraries. Avoid competing state-management
  solutions.
- Centralise the API base URL per environment; do not scatter
  Raspberry Pi IP addresses in the code.
- Handle loading, empty, success, validation, timeout, offline, and
  server-error states.
- Optimise front-desk flows for few taps and guard against duplicate
  payment submissions.
- Never embed secrets or admin credentials in source code.
- Use Kotlin platform channels only for genuine Android-specific
  requirements such as a native SDK, USB, NFC, Bluetooth, or platform
  service. Do not add Kotlin merely because the app runs on Android.

## Backend guidelines

- Use Rust types and clear module boundaries.
- Use SQLx with bound query parameters and embedded explicit SQL migrations.
- Use Axum state/extractors for database access and authenticated users.
- Use transactions for multi-step operations such as invoice/payment
  creation.
- Enforce important invariants in both application logic and database
  constraints where practical.
- Use structured logs and request IDs. Redact passwords, tokens, and
  unnecessary personal data.
- Configure database connections for Raspberry Pi resources.
- Keep secrets in environment variables or protected configuration
  files.
- Do not run destructive schema creation/migrations automatically on
  every startup.
- Make background tasks restart-safe and idempotent.

## Security, privacy, and reliability

- Keep PostgreSQL on a private Docker network or loopback. Do not
  expose it to the public internet.
- Do not configure public router port forwarding to the Pi.
- Restrict terminal ingestion to the trusted LAN and known device
  identities where supported.
- Use HTTPS where practical, especially across untrusted networks. Do
  not describe plain HTTP as encrypted.
- Hash passwords with a modern password-hashing algorithm; never store
  plaintext passwords.
- Enforce role permissions on the server, not just by hiding UI
  controls.
- Audit sensitive business operations.
- Keep the Pi and dependencies updated; configure firewall rules.
- Back up PostgreSQL to the external HDD. Document backup rotation and
  perform restore tests. A backup is not proven until restoration
  succeeds.
- Prefer reliable storage for the live database; use the external HDD
  primarily for backups unless there is a specific reason otherwise.
- Document recovery after power loss, database corruption, and
  network/device outages.

## Development workflow

Develop on macOS using VS Code. The Android tablet can be connected with
Android Wireless Debugging/ADB; USB is optional after wireless pairing.

Useful Flutter commands:

```bash
flutter doctor
flutter devices
flutter run
flutter analyze
flutter test
flutter build apk --release
```

Typical backend checks may include:

```bash
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
replab-server --env-file /etc/replab/owner.env migrate
```

Inspect the repository and use its actual scripts/dependency manager; do
not assume these commands or paths exist.

Target deployment: Raspberry Pi 5 (8 GB), Raspberry Pi OS 64-bit,
Rust/Axum, PostgreSQL, external HDD for backups, and an Android tablet
connected over the gym LAN.

Keep development, test, and production configuration separate. Never
commit `.env` files, credentials, database dumps, biometric data, or
real member records.

## Repository workflow for Copilot

Before changing code:

1.  Inspect the repository tree, README, manifests, existing
    architecture, and tests.
2.  Identify implemented features. Do not recreate working modules or
    replace established choices without reason.
3.  Identify impact across Flutter, API, database, and device
    integration.
4.  For uncertain eSSL behaviour, request captured device traffic or a
    test payload. Never invent protocol details.

When implementing:

1.  Make the smallest coherent change.
2.  Separate UI, API, domain logic, persistence, and device protocol
    concerns.
3.  Add explicit SQL migrations for schema changes.
4.  Add tests for business rules, validation, failure paths, retries,
    and duplicate handling.
5.  Update documentation and example configuration.
6.  Run relevant formatters, static analysis, and tests.
7.  Report exactly what commands were run, what changed, and what
    remains untested.

Do not rewrite the whole application to solve a small issue. Do not
silently change frameworks, database engines, deployment assumptions, or
API contracts. Do not use fake success responses in production code. Do
not swallow exceptions or silently discard attendance/payment events.
Avoid unnecessary microservices, message brokers, Kubernetes, and cloud
dependencies for this single-location system. Obtain approval before
destructive database changes.

## Testing expectations

Add tests for changed behaviour. Important cases include:

- Subscription start/end date boundaries and expired, frozen,
  cancelled, and future subscriptions.
- Unknown terminal user IDs.
- Duplicate event delivery, retries, and out-of-order events.
- Device event time versus server receive time.
- Partial payments, overpayment policy, refunds, and invoice balances.
- Repeated/concurrent payment submissions.
- Role-based access to member and payment operations.
- Transaction rollback when a multi-step operation fails.
- Backup creation and restore procedure.

Use synthetic data. Never use real biometric templates or real member
personal data in automated tests.

## Expected assistant behaviour

For implementation requests:

- Summarise intended behaviour and assumptions that affect data
  integrity or hardware behaviour.
- Inspect existing code before proposing file changes.
- Give a concise plan for changes spanning multiple layers.
- Implement complete, runnable code when implementation is requested.
- Explain migrations, configuration, and manual hardware setup.
- Report test results honestly and distinguish verified behaviour from
  assumptions.
- Ask a focused clarification before proceeding when ambiguity could
  cause data loss, financial errors, security issues, or incorrect
  attendance.
