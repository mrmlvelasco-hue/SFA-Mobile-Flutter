# SFA Mobile (Flutter)

Flutter rewrite of the SFA sales-force-automation mobile app. The previous mobile app
(not in this repo) was React Native; this is a fresh app written against the same
backend contract, not a direct code port. It talks to the Python/FastAPI backend in the
`SFA-API` repo's `/api/v1` routes.

## Status (2026-11-17) -- Milestone 1

This is the **first milestone only**: project skeleton, theming, API client, and the full
auth flow (login + logout), plus an app shell (drawer) listing every section from the
original app as a placeholder ("Coming soon") screen. **No business screens are built
yet** -- order management, inventory, payments, etc. are all still RN-only. See
"Known gaps" below and the project's area notes for the planned build order.

Deliberately deferred from this milestone (will be added in later passes):
- Offline-first local storage (the RN app used SQLite + AsyncStorage)
- GPS / geofencing (login's `lat`/`lng` are currently hardcoded to `0.0`)
- Maps, signature capture, native device checks (root/jailbreak detection, etc.)

## Known gaps

- **Forgot/change/reset password**: the backend has no mobile-facing routes for these yet
  (`/api/v1/forgot-password`, `/reset-password`, `/change-password`,
  `/reset-forgot-password` -- see the RN app's `src/services/authApi.js` for what the old
  app called). The "Forgot password?" link currently opens a placeholder screen saying so.
  These need to be added to `SFA-API` before the Flutter screens for them are worth building.
- **No session refresh on resume**: if the app is reopened with a saved token, it goes
  straight to the signed-in shell but `AuthState.user` is `null` until the next login,
  because there's no `/me`-style endpoint to re-fetch the user. Add one on the backend, or
  make the Flutter app re-send the user payload some other way, before relying on this.
- **`ip`/device identity fields**: `device_name` is just the OS name/version; `ip` is a
  stub `"0.0.0.0"`. The backend only logs these to the audit trail today, so this is safe,
  but tighten it if that ever changes.

## I cannot verify this app runs -- you are the first to build it

I wrote this by hand without being able to run `flutter pub get`, `flutter analyze`,
`flutter test`, or `flutter build` myself -- this sandbox has no network access to
`pub.dev` or the Flutter engine download host. Everything below is what *should* work,
not what's been proven to work. Please run it and tell me what breaks; I'll fix forward
from real error output.

## Set up Flutter tooling (one-time, on your machine)

1. Install the Flutter SDK: https://docs.flutter.dev/get-started/install
2. Run `flutter doctor` and resolve anything it flags (Android SDK / Xcode / etc.)
3. From this repo's root, run:

       flutter create .

   This is safe to run on an existing Flutter project -- it does **not** overwrite
   `lib/` or `pubspec.yaml`; it only fills in the platform scaffolding (`android/`, `ios/`,
   `.metadata`, etc.) that isn't committed here (hand-writing Gradle/Xcode project files
   without being able to test them is riskier than letting the real `flutter` tool
   generate them).

## Run it

Point the app at your running `SFA-API` backend (see that repo's README to get it up) via
`--dart-define`:

    flutter pub get
    flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000 --dart-define=APP_VERSION=1.0.0

- `API_BASE_URL`:
  - Android emulator → `http://10.0.2.2:8000` (alias for your host machine's localhost)
  - iOS simulator / macOS / web → `http://localhost:8000`
  - physical device → your machine's LAN IP, e.g. `http://192.168.1.50:8000`
- `APP_VERSION` must exactly match the backend's `application_version` setting (in the
  `settings` table) or every login attempt is rejected with "There is an updated version
  of the SFA Mobile App...". Check what your seeded/UAT database has that setting set to.

Without `--dart-define` overrides it defaults to `http://localhost:8000` / `1.0.0`.

## Test every update

    flutter test                 # all widget + unit tests
    flutter test test/auth_state_test.dart   # just one file, while iterating
    flutter analyze              # static analysis -- run this after every change too

Current tests (`test/`):
- `login_screen_test.dart` -- validation errors on empty submit; both fields render
- `auth_state_test.dart` -- login success/failure flow against a fake repository (no
  network calls, so this doesn't need the backend running)

There is no integration/E2E test yet that actually talks to a running `SFA-API` instance.
Once more screens exist, consider adding one with `integration_test` against a local
backend + seeded test database (the `sfa-api` repo's `tests/conftest.py` pattern is a
good model for the seed data).

## Layout

    lib/
      core/            api_config.dart (base URL/app version), api_client.dart (Dio + response envelope),
                       token_storage.dart (secure token/device-id persistence),
                       device_info_service.dart (device id/name, lat/lng/ip stubs),
                       app_colors.dart, app_theme.dart (ported from the RN app's colors.js)
      features/
        auth/          auth_repository.dart (calls /api/v1/login, /logout),
                       auth_state.dart (ChangeNotifier session state), login_screen.dart, sfa_user.dart
        home/          drawer_shell.dart (post-login app shell + drawer), menu_items.dart (ported menu list)
        placeholder/   coming_soon_screen.dart (stand-in for unbuilt sections)
      main.dart        MaterialApp + AuthGate (Login vs DrawerShell by auth status)
    test/              widget + unit tests (see above)

## Next milestones (planned, not started)

In the order the original app's drawer lists them, once a milestone is picked up:
1. Route Call Schedule (the home/landing screen after login)
2. Order Management (add order, misc discounts, digital signature, order summary) --
   the largest module
3. Order Status
4. Payment Collection
5. Outlet Inventory / DC Inventory / Floor Stock Inventory
6. Sales Return, Subsidiary Ledger, Sales Inquiries, Route Productivity,
   Non-Sales Activities, Empties Pullout, Customer Master Data, Feedback

Each milestone should land as its own PR/commit with its own tests, same cadence as the
backend work.
