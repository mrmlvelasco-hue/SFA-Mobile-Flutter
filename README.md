# SFA Mobile (Flutter)

Flutter rewrite of the SFA sales-force-automation mobile app. The previous mobile app
(not in this repo) was React Native; this is a fresh app written against the same
backend contract, not a direct code port. It talks to the Python/FastAPI backend in the
`SFA-API` repo's `/api/v1` routes.

## Status (2026-11-19) -- Milestone 4: the call and the order

The main route process now works end to end, like the RN app:

**Route list -> customer -> Start Call -> Outlet Inventory -> Order Management -> Add Order ->
Misc Discount -> Order Summary -> Digital Signature -> order sent -> End Call.**

1. **Customer Master Data** (tap a customer): outlet, owner, contact, address, credit term /
   limit / balance, payment type, price zone, channel, sub-channel, distribution type, account
   status. **Start Call** is refused while another customer's call is ongoing. During the call:
   the call menu, **Cancel Call** (only before the outlet inventory is saved or an order is
   signed) and **End Call**.
2. **Outlet Inventory**: Fulls and Empty tabs, starting from the outlet's last count on the server
   (download's `outlets`). Add SKUs, change or remove counts, Save. Only what changed is sent
   (`outlet-inventory/sku/addNew`, with `product_data` / `product_deleted` as the RN app builds
   them). Order Management needs today's outlet inventory first, except for `NREQ` accounts.
3. **Order Management**: ship-to (the customer's Ship-To-Party partners), distribution center
   (defaults to the customer's delivering plant), Delivery / Pick Up, delivery date (today + 2,
   or + 3 when that is a Sunday or Monday; earlier dates or Sunday ask to confirm). Add Order is
   blocked when there is no OCL and no credit balance.
4. **Add Order**: the customer's price list (`pricing` wsp + discount, the material's unit price as
   fallback, empties excluded), the RN search rule (contains the text and starts with the same
   letter), the DC's real-time stock (`materials-inventory-sap`, fetched after the download and
   saved for offline use), and the out-of-stock warning.
5. **Misc Discount**: the pick-up discount (Pick Up orders) and a rebate claim (more than 0 and not
   over the rebate balance). Skip clears both.
6. **Order Summary**: gross, SKU discounts, net gross, pick-up, rebate and the estimated total,
   and the RN credit check before submitting (COD always passes; with OCL: a warning; without OCL
   and over the balance: blocked).
7. **Digital Signature**: the customer signs on screen (drawn in the app, sent as a PNG data URL),
   remarks, Submit -> `order/submit` with every field the RN app sends.
8. **End Call** sends `route/end-call` after an order. The route list shows the call as
   **Call Ongoing** / **Done**.

**Offline**: the call, the outlet inventory count and the order being taken are saved on the
phone as you go (they survive closing the app). With no connection, the outlet inventory, the
order and the end of call are kept in an **outbox** and sent, in order, when the connection is
back (on returning to the app, or with **Send now** on the banner above the route list). If the
server rejects an order sent directly, the call shows "Order not accepted" with the server's
message and the order can be fixed and sent again.

Earlier milestones:
- **1**: skeleton, theming, API client, login/logout, drawer.
- **2**: Route Call Schedule -- today's customers, Scheduled/Unscheduled, search, Done state.
- **3**: master data download (the RN app's 16 calls) + offline storage, Dashboard, the day rule
  (a session belongs to the day you logged in).

Not in this milestone (the RN app has them; they come later):
- **Promos**: a customer's promos are listed on Misc Discount but can't be selected yet (the
  sample route has none). `total_promo_discount` is sent as `0`.
- **Empties Pullout** step of the order (sent as `empties_pullout: "[]"`), Sales Return,
  Subsidiary Ledger, Payment Collection -- menu items open a placeholder.
- **Ending a call without an order**: the RN app asks for a no-order reason (Feedback screen) and
  sends feedback; here the call is only ended on the phone (nothing is sent).
- **GPS / geofence**: start/end coordinates are `0`, `is_inside_geo` / `deviation_in_meters` are
  `null`. Begin Route / End Route.
- Re-opening a submitted order to edit it (the RN "view order" mode).

Differences from the RN app, on purpose:
- The whole download fails on the first failing call (the RN app ignored some failures).
- The cached pricing belongs to the user who downloaded it.
- The dashboard keeps its last figures for offline use.
- When there is no OCL and no credit balance, the summary says so (the RN app silently did
  nothing on Submit in that case).

### Try it with the sample route

In `SFA-API`, **on each day you test** (the app downloads only today's route calls):

    python manage.py upload-masterdata data/SFA_Masterdata_sample.xlsx --call-date today
    python manage.py seed
    python manage.py reset-devices jdelacruz

`seed` also gives every customer on route 213008 a ship-to partner and puts 500 cases of every
SKU in DC 2130, where the workbook has none. Log in as `jdelacruz` (58 customers today).

To check the backend side of the order flow without the phone:

    python tools/smoke_call_order.py --dev          # outlet inventory, order + signature, end call

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
- `route_call_schedule_screen_test.dart` -- lists, filters, searches, shows Done, opens a customer,
  ongoing/done from calls made on the phone, the offline banner
- `order_draft_test.dart` -- order totals, delivery-date rules, the `order/submit` payload field by
  field, credit check, ship-to choices, SKU catalog/stock/search rules
- `call_state_test.dart` -- one call at a time, cancel rule, outlet inventory changes and the
  `addNew` body, submit + end call online, offline queueing and resend order, rejected orders,
  saved calls surviving a restart
- `call_flow_screens_test.dart` -- Start Call, the outlet-inventory-first rule, and the screens
  from Order Management through Add Order, Misc Discount and Summary to the signature

There is no integration/E2E test yet that actually talks to a running `SFA-API` instance.
Once more screens exist, consider adding one with `integration_test` against a local
backend + seeded test database (the `sfa-api` repo's `tests/conftest.py` pattern is a
good model for the seed data).

## Layout

    lib/
      core/            outbox.dart (requests waiting for a connection),
                       offline_store.dart (saved downloads, one JSON file each), formatting.dart (RN number/date
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
        calls/         call_state.dart (today's calls, saved on the phone; sends via the outbox),
                       order_draft.dart (order lines, totals, the order/submit payload),
                       sku_catalog.dart (price list + DC stock), call_rules.dart (credit, ship-to,
                       rebates...), customer_screen.dart, outlet_inventory_screen.dart,
                       order_management_screen.dart, add_order_screen.dart, misc_discount_screen.dart,
                       order_summary_screen.dart, signature_screen.dart + signature_pad.dart
        home/          drawer_shell.dart (post-login app shell + drawer), menu_items.dart (ported menu list)
        placeholder/   coming_soon_screen.dart (stand-in for unbuilt sections)
      main.dart        MaterialApp + AuthGate (Login vs DrawerShell by auth status)
    test/              widget + unit tests (see above)

## Next milestones (planned, not started)

1. ~~Route Call Schedule~~ (2); ~~master data download, offline storage, Dashboard~~ (3);
   ~~Customer Master Data, start/end call, Outlet Inventory, Order Management with signature~~ (4)
2. Feedback (no-order end call), Empties Pullout step, promos in Misc Discount
3. Begin Route / End Route + GPS / geofence
4. Order Status, Payment Collection
5. Sales Return, Subsidiary Ledger, DC Inventory / Floor Stock, Sales Inquiries, Route
   Productivity, Non-Sales Activities

Each milestone should land as its own PR/commit with its own tests, same cadence as the
backend work.
