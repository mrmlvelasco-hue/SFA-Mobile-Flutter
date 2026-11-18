# SFA Mobile (Flutter)

Flutter rewrite of the SFA sales-force-automation mobile app. The previous mobile app
(not in this repo) was React Native; this is a fresh app written against the same
backend contract, not a direct code port. It talks to the Python/FastAPI backend in the
`SFA-API` repo's `/api/v1` routes.

## Status (2026-11-18) -- Milestone 2

- **Milestone 1** (done): project skeleton, theming, API client, login/logout, app shell (drawer)
  with every original section listed.
- **Milestone 2** (done): **Route Call Schedule** -- the first screen after login. Lists today's
  customers to visit (from `POST /api/v1/download-datav2`), with the Scheduled/Unscheduled filter,
  outlet-name search, numbering in route order, pull-to-refresh, and the green **Done** state for
  customers that already have a matching order (from `download-datav2/order-details`). The session
  is now saved, so reopening the app keeps you signed in.

To see data on this screen locally, run `python manage.py seed` in `SFA-API` **on the day you test**
-- it creates today's demo route calls for `jdelacruz` (5 customers; `DEMO0002` shows as Done).

Not ported yet from the RN Route Call Schedule:
- the map of customer locations behind the list (needs a maps package + API key; deferred with GPS)
- the "You are offline" banner (needs offline storage)
- the orange "Call Ongoing" state (comes with the start-call flow)
- tapping a customer opens a placeholder -- **Customer Master Data** is the next screen to port

Deliberately deferred (later passes):
- Offline-first local storage (the RN app used SQLite + AsyncStorage)
- GPS / geofencing (login's `lat`/`lng` are currently hardcoded to `0.0`)
- Maps, signature capture, native device checks (root/jailbreak detection, etc.)

## Known gaps

- **Forgot/change/reset password**: the backend has no mobile-facing routes for these yet
  (`/api/v1/forgot-password`, `/reset-password`, `/change-password`,
  `/reset-forgot-password` -- see the RN app's `src/services/authApi.js` for what the old
  app called). The "Forgot password?" link currently opens a placeholder screen saying so.
  These need to be added to `SFA-API` before the Flutter screens for them are worth building.
- **Session restore uses the saved login response**: reopening the app restores the user saved at
  the last login (there's no `/me` endpoint to re-fetch it). If the server rejects the token
  ("Unauthenticated."), the app returns to the login screen with "Your session has expired".
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

Current tests (`test/`) -- none need the backend running; they use fakes from `test/helpers.dart`:
- `login_screen_test.dart` -- validation errors on empty submit; both fields render
- `auth_state_test.dart` -- login success/failure, session save/restore, logout
- `route_call_state_test.dart` -- scheduled/unscheduled rules, sorting, search, one row per
  customer, the Done rule, backend errors, expired token
- `route_call_schedule_screen_test.dart` -- the screen loads, lists, filters, searches, shows
  Done, and opens a customer

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
        route_calls/   route_call.dart (model), route_call_repository.dart (download-datav2 calls),
                       route_call_state.dart (filter/search/done logic), route_call_schedule_screen.dart
        home/          drawer_shell.dart (post-login app shell + drawer), menu_items.dart (ported menu list)
        placeholder/   coming_soon_screen.dart (stand-in for unbuilt sections)
      main.dart        MaterialApp + AuthGate (Login vs DrawerShell by auth status)
    test/              widget + unit tests (see above)

## Next milestones (planned, not started)

In the order the original app's drawer lists them, once a milestone is picked up:
1. ~~Route Call Schedule~~ (done, milestone 2)
2. Customer Master Data (opened by tapping a customer) + start call
3. Order Management (add order, misc discounts, digital signature, order summary) --
   the largest module
4. Order Status
5. Payment Collection
6. Outlet Inventory / DC Inventory / Floor Stock Inventory
7. Sales Return, Subsidiary Ledger, Sales Inquiries, Route Productivity,
   Non-Sales Activities, Empties Pullout, Customer Master Data, Feedback

Each milestone should land as its own PR/commit with its own tests, same cadence as the
backend work.
