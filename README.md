# SkorX app

One Flutter app for players, tournament organizers and referees in racket sports (pickleball today; badminton and table tennis are seeded). It ships under the live store id `com.skorx.pickleball`, so it installs as an update to the current player app.

The app is one of two clients of the SkorX platform API. The API (NestJS + Prisma + PostgreSQL) and the web TMS (Next.js) live in a separate repo, `smit-dev-skorx-frontend`. There is no separate mobile backend.

## Start here

| If you want to… | Read |
|---|---|
| Understand the overall design | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Find where a feature lives (app, API, tables, tests) | [docs/MODULES.md](docs/MODULES.md) |
| Learn the coding rules for this repo | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Read a feature's spec | `docs/<FEATURE>.md` (listed in MODULES.md) |
| See the latest audit and open risks | [docs/AUDIT-2026-09-28.md](docs/AUDIT-2026-09-28.md) |

## Tech stack

- Flutter 3.47 / Dart 3, Riverpod for state, go_router for navigation.
- Local-first casual scoring: atomic per-match files on the device plus a sync engine (see [docs/OFFLINE-SCORING.md](docs/OFFLINE-SCORING.md)).
- REST API at `/api/v1`, JWT access tokens plus a rotating refresh token.

## Folder structure

```text
lib/
  main.dart            entry point
  app/                 app shell: routing, theme, intro animation
  core/                cross-feature plumbing: API client, auth tokens, sync, permissions
  design/              SkorX design system widgets (player look)
  shared/ui/           generic UI components used by several features
  sports/              one folder per sport: rules, scoring engine, categories
  features/<feature>/  one folder per business feature
    data/              models, repositories (API + sample), controllers
    ui/                screens and widgets
test/                  mirrors lib/ (features/, sports/, core/, app/)
docs/                  architecture, module map and feature specs
```

A feature's UI never calls `ApiClient` directly. It reads a Riverpod provider from the feature's `data/` folder, which picks the API repository or the sample one.

## Local setup

Install everything on the D: drive (the C: drive is nearly full on the main dev machine).

```bash
# Tools used on the main machine
export PATH="/d/dev/flutter/bin:$PATH"
export PUB_CACHE='D:\dev\pub-cache' GRADLE_USER_HOME='D:\dev\gradle' \
       JAVA_HOME='D:\dev\jdk-17' ANDROID_HOME='D:\dev\android-sdk'

flutter pub get
flutter test                      # whole suite, no device or network needed
flutter run -d <device-id>        # debug build: sample data, dev sign-in
```

### Build-time configuration

The app has no `.env` file; configuration is passed with `--dart-define`. Copy [dart_defines.example.json](dart_defines.example.json) to `dart_defines.json` (git-ignored), edit it, and run:

```bash
flutter run --dart-define-from-file=dart_defines.json
```

| Key | Default | Meaning |
|---|---|---|
| `API_BASE_URL` | `http://10.0.2.2:4000/api/v1` | API root. `10.0.2.2` is the host machine from the Android emulator; use the PC's LAN IP for a real phone. |
| `REAL_AUTH` | `false` | Use real phone + WhatsApp OTP sign-in in a debug build. Release builds always use it unless `DEV_AUTH` is set. |
| `DEV_AUTH` | `false` | Force the offline dev sign-in in a release build. Never ship with this. |
| `GST_RATE` | `0.18` | GST used by the dev billing repository only. |

Never put secrets in dart-defines: anything compiled into the app can be read from the APK.

### Running against the real API

Start the API from `smit-dev-skorx-frontend/backend` (see its README), then run the app with `REAL_AUTH=true` and `API_BASE_URL` pointing at it. In development the OTP code is printed in the API log.

## Tests

```bash
flutter test                         # all
flutter test test/sports             # scoring engines and shared vectors
flutter test test/features/offline_sync_test.dart
```

Anything that uses real file I/O or the network in widget tests hangs on Windows. Gate it on the `FLUTTER_TEST` environment variable, as `matchStoreProvider` does.

Server-side end-to-end checks live in `smit-dev-skorx-frontend/backend/scripts/` and need a running API.
