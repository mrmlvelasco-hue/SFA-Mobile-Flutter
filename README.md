# SFA Mobile (Flutter)

Flutter rewrite of the SFA sales-force-automation mobile app. The previous mobile app
(not in this repo) was React Native; this is a fresh app written against the same
backend contract, not a direct code port. It talks to the Python/FastAPI backend in the
`SFA-API` repo's `/api/v1` routes.

## Status (2026-11-18) -- Milestone 3

After login the app works the way the RN app does:

1. **Login** -> **Downloading data**: the app downloads the master data -- the same 16
   `download-datav2` calls, in the same order and with the same payloads, as the RN app's
   `DownloadData.js` (route calls, materials, promo discounts, empties, order details, sales
   returns, material inventory, collections, outlets, receivables, rebates, pickup discounts,
   partners, pricing, sales volume, customer promos). The screen names each step and its percent;
   on failure it names the failing step, with Retry and Log out.
2. The download is **saved on the phone**, so for the rest of the day the app opens and runs
   **without internet**. Every screen reads the saved data, not the server.
3. **Pricing** is cached separately and re-downloaded only when the server flags a price update
   (`constants.price_update`), as in the RN app.
4. **Dashboard** is the first screen: "As of <yesterday>" and five gauges (Revenue NSR, Volume Raw,
   Volume 8oE, Volume Physical, Revenue GSR) from `actual-coob-dashboard`. The last figures are
   saved, so offline it shows those, marked with when they were fetched.
5. **New day**: like the RN app, a session belongs to the day you logged in. Opening (or returning
   to) the app on a later day ends it with "You haven't logged out from yesterday's session.
   Please re-login." and the old download is deleted; logging in downloads fresh data.

Milestones so far:
- **1**: skeleton, theming, API client, login/logout, drawer.
- **2**: Route Call Schedule -- today's customers, Scheduled/Unscheduled, search, Done state.
  It now reads the saved download (no pull-to-refresh: data is downloaded once after login).
- **3** (this one): master data download + offline storage, Dashboard, day rule.

Differences from the RN app, on purpose:
- The whole download fails on the first failing call; the RN app ignored some failures (it only
  checked 9 of the 16 responses) and could save incomplete data.
- The cached pricing belongs to the user who downloaded it; the RN app reused one device-wide
  pricing cache for whoever logged in next.
- The dashboard keeps its last figures for offline use; the RN dashboard is blank offline.

To see real-looking data locally, in `SFA-API` load the master-data workbook (sample route
`213008`) and set up `jdelacruz` -- **on each day you test**, since the app downloads only today's
route calls:

    python manage.py upload-masterdata data/SFA_Masterdata_sample.xlsx --call-date today
    python manage.py seed

Log in as `jdelacruz`: 58 customers today (16 scheduled, 42 unscheduled), ~13,700 prices.
`python tools/smoke_mobile_download.py --dev` in `SFA-API` runs the same download sequence against
your backend and reports each step -- use it to check the backend side when the app's download fails.

Not ported yet:
- **Begin Route** (drawer button -> "Are you sure you want to begin route?" -> GPS fix -> start
  of the route day) -- next milestone; needs GPS and a queue for actions done offline
- the map behind the route list, the offline banner, the "Call Ongoing" state
- the password-expiry reminder after the download; the DC-inventory/floor-stock prefetch
- tapping a customer opens a placeholder (Customer Master Data is a later milestone)

Deliberately deferred (later passes):
- GPS / geofencing (login's `lat`/`lng` are currently hardcoded to `0.0`)
- Maps, signature capture, native device checks (root/jailbreak detection, etc.)

## Known gaps

- **Forgot/change/reset password**: the backend has no mobile-facing routes for these yet
  (`/api/v1/forgot-password`, `/reset-password`, `/change-password`,
  `/reset-forgot-password` -- see the RN app's `src/services/authApi.js` for what the old
  app called). The "Forgot password?" link currently opens a placeholder screen saying so.
  These need to be added to `SFA-API` before the Flutter screens for them are worth building.
- **Session restore uses the saved login response**: reopening the app the same day restores the
  user saved at login (there's no `/me` endpoint to re-fetch it). If the server rejects the token
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
- `auth_state_test.dart` -- login success/failure, session save/restore, the new-day rule, logout
- `master_data_state_test.dart` -- the 16 calls in the RN order with the RN payloads, saving and
  restoring today's download offline, the pricing-cache rule, failures, expired token
- `download_screen_test.dart` -- progress text, failure message, Retry
- `dashboard_state_test.dart` -- query parameters, gauge figures/formatting, offline fallback
- `formatting_test.dart` -- the number/date rules ported from the RN utils
- `route_call_state_test.dart` -- scheduled/unscheduled rules, sorting, search, one row per
  customer, the Done rule
- `route_call_schedule_screen_test.dart` -- lists, filters, searches, shows Done, opens a customer

There is no integration/E2E test yet that actually talks to a running `SFA-API` instance.
Once more screens exist, consider adding one with `integration_test` against a local
backend + seeded test database (the `sfa-api` repo's `tests/conftest.py` pattern is a
good model for the seed data).

## Layout

    lib/
      core/            offline_store.dart (saved downloads, one JSON file each), formatting.dart (RN number/date
                       rules), safe_notifier.dart,
                       api_config.dart (base URL/app version), api_client.dart (Dio + response envelope),
                       token_storage.dart (secure token/device-id persistence),
                       device_info_service.dart (device id/name, lat/lng/ip stubs),
                       app_colors.dart, app_theme.dart (ported from the RN app's colors.js)
      features/
        auth/          auth_repository.dart (calls /api/v1/login, /logout),
                       auth_state.dart (ChangeNotifier session state), login_screen.dart, sfa_user.dart
        master_data/   master_data_state.dart (the 16-call download, saving/restoring, pricing cache),
                       master_data_repository.dart, download_screen.dart
        dashboard/     dashboard_state.dart, dashboard_screen.dart, gauge_card.dart
        route_calls/   route_call.dart (model), route_call_state.dart (filter/search/done logic, from the
                       saved download), route_call_schedule_screen.dart
        home/          drawer_shell.dart (post-login app shell + drawer), menu_items.dart (ported menu list)
        placeholder/   coming_soon_screen.dart (stand-in for unbuilt sections)
      main.dart        MaterialApp + AuthGate (Login vs DrawerShell by auth status)
    test/              widget + unit tests (see above)

## Next milestones (planned, not started)

In the order the original app's drawer lists them, once a milestone is picked up:
1. ~~Route Call Schedule~~ (done, milestone 2); ~~master data download, offline storage,
   Dashboard~~ (done, milestone 3)
2. Begin Route / End Route (GPS, offline queue for actions done without internet)
3. Customer Master Data (opened by tapping a customer) + start call
4. Order Management (add order, misc discounts, digital signature, order summary) --
   the largest module
5. Order Status
6. Payment Collection
7. Outlet Inventory / DC Inventory / Floor Stock Inventory
8. Sales Return, Subsidiary Ledger, Sales Inquiries, Route Productivity,
   Non-Sales Activities, Empties Pullout, Customer Master Data, Feedback

Each milestone should land as its own PR/commit with its own tests, same cadence as the
backend work.
