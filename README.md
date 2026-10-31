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

Serve the web preview at `http://localhost:8080`:

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

## Database

PostgreSQL is available to the dev container at `db:5432`. Compose loads
the local credentials from `.env`; do not commit that file.