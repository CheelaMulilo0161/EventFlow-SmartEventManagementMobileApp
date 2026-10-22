# EventFlow setup and operations

This guide covers a fresh local setup on Windows, API and database commands, connecting a
phone or emulator, and common problems.

## 1. Prerequisites

| Tool | Requirement |
| --- | --- |
| Node.js | 20 or newer |
| npm | Included with Node.js |
| PostgreSQL | 18 recommended; binaries must include `initdb`, `pg_ctl`, `createdb` |
| Flutter | 3.47 or newer, Dart 3.13 or newer |
| Android | Android SDK, build tools, platform tools (`adb`) |
| Java | 17 (bundled with current Flutter/Android tooling) |

Check the toolchain:

```powershell
node --version
npm --version
flutter doctor
& "C:\Android\Sdk\platform-tools\adb.exe" version
```

If PostgreSQL is not installed at `C:\Program Files\PostgreSQL\18\bin`, set `PG_BIN` before
running the database scripts:

```powershell
$env:PG_BIN = "C:\Program Files\PostgreSQL\17\bin"
```

The database scripts are PowerShell scripts. On macOS or Linux, create the databases with
your local PostgreSQL tools and point `DATABASE_URL` / `TEST_DATABASE_URL` at them.

## 2. Install backend dependencies

```powershell
cd api
npm install
```

Create the environment file:

```powershell
Copy-Item .env.example .env
```

Edit `api\.env`:

```dotenv
PORT=3000
DATABASE_URL=postgres://postgres@localhost:5433/eventflow
TEST_DATABASE_URL=postgres://postgres@localhost:5433/eventflow_test
JWT_SECRET=replace-with-a-long-random-secret
TICKET_SECRET=replace-with-a-different-long-random-secret
BOOKING_HOLD_MINUTES=15
BCRYPT_ROUNDS=12
```

Use different, random values for both secrets. They are development defaults only when
missing, and production deployments must supply real secrets.

## 3. Database lifecycle

The repository keeps an isolated local cluster in `.pgdata` and uses port **5433**. This
avoids colliding with a PostgreSQL service already running on the default port 5432.

### First-time initialization

```powershell
# From the repository root
.\scripts\db-init.ps1
```

The script:

1. Runs `initdb` with trust authentication for local development.
2. Starts the cluster on port 5433.
3. Creates `eventflow` and `eventflow_test`.

`initdb -A trust` is for local development only. Do not use trust authentication for a
shared or production database.

### Start and stop

```powershell
.\scripts\db-start.ps1
.\scripts\db-stop.ps1
```

Or from `api`:

```powershell
npm run db:start
npm run db:stop
```

Check the cluster:

```powershell
& "C:\Program Files\PostgreSQL\18\bin\pg_ctl.exe" -D .\.pgdata status
```

### Reset the development database

Stop the API, then either drop and recreate the databases or remove `.pgdata` and rerun
`db-init.ps1`. Removing `.pgdata` deletes all local data.

```powershell
.\scripts\db-stop.ps1
Remove-Item -Recurse -Force .\.pgdata
.\scripts\db-init.ps1
```

## 4. Migrate and seed

```powershell
cd api
npm run migrate
npm run seed
```

Or run both:

```powershell
npm run setup
```

The seed is repeatable: demo users are upserted and existing demo events/bookings are not
duplicated. Re-running the seed resets the demo users' passwords to `Password123!`.

Demo accounts:

| Role | Email | Password |
| --- | --- | --- |
| Attendee | `attendee@eventflow.zm` | `Password123!` |
| Organizer | `organizer@eventflow.zm` | `Password123!` |
| Admin | `admin@eventflow.zm` | `Password123!` |

## 5. Run the API

Development mode with automatic restart:

```powershell
npm run dev
```

Production-style build and start:

```powershell
npm run build
npm start
```

Verify:

```powershell
Invoke-RestMethod http://localhost:3000/health
```

The server binds to `0.0.0.0:3000`, so phones on the same network can reach it through the
computer's LAN address. On startup it runs pending migrations and starts the booking-hold
expiry job.

## 6. Run the Flutter app

```powershell
cd mobile
flutter pub get
flutter analyze
flutter test
```

Run on a connected Android device:

```powershell
flutter devices
flutter run
```

### API address by target

| Target | API base URL | Notes |
| --- | --- | --- |
| Physical phone on Wi-Fi | `http://<computer-LAN-IP>:3000` | Same Wi-Fi network; allow Node.js through Windows Firewall |
| Android emulator | `http://10.0.2.2:3000` | `10.0.2.2` is the host loopback alias |
| USB device with adb reverse | `http://127.0.0.1:3000` | Run `adb reverse tcp:3000 tcp:3000` first |

Find the computer's LAN address:

```powershell
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
  Select-Object InterfaceAlias, IPAddress
```

Change the address in the app from the button on the login screen or from **Profile > API
server**. The value is stored locally and survives restarts.

The compiled default is in `mobile/lib/config.dart`. Override it at build time:

```powershell
flutter build apk --release --split-per-abi --dart-define=API_BASE_URL=http://YOUR_IP:3000
```

A saved in-app address overrides the compiled default. If the saved address is wrong,
change it from the login screen.

## 7. Build and install the APK

```powershell
cd mobile
flutter build apk --debug
flutter build apk --release --split-per-abi
```

Install the arm64 build on most modern phones:

```powershell
& "C:\Android\Sdk\platform-tools\adb.exe" install -r "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
```

If Android reports a signature or downgrade error, uninstall the previous copy first:

```powershell
& "C:\Android\Sdk\platform-tools\adb.exe" uninstall zm.eventflow.eventflow
```

The current release build is signed with the Android debug key so it can be sideloaded.
Configure a private release keystore before publishing to Google Play or distributing
updates outside a demo environment.

## 8. Demo walkthrough

### Attendee

1. Log in as `attendee@eventflow.zm`.
2. Browse **Discover** and open an event.
3. Select one or more ticket types and tap **Reserve**.
4. At checkout, enter a phone number and tap **Pay**.
5. Tap **Approve in demo** in the simulated mobile-money sheet.
6. Open **Tickets** to see the QR code and short code.

Reservations hold capacity for 15 minutes. Expired holds are released by the API job.

### Organizer

1. Log out and log in as `organizer@eventflow.zm`.
2. Open **My events** and select a published event.
3. Tap **Scan** to open the camera, or use **Manual check-in** for the short code.
4. The first valid scan marks the ticket used. A second scan reports `already_used`.
5. The event dashboard shows revenue, confirmed bookings, and check-in progress.

### Admin

1. Log in as `admin@eventflow.zm`.
2. Open **Profile** to see platform statistics.
3. Organizer features are available across all events.

## 9. Useful commands

| Command | Purpose |
| --- | --- |
| `npm run dev` | Start API with watch mode |
| `npm run build` | Compile TypeScript to `dist` |
| `npm start` | Run the compiled API |
| `npm run migrate` | Apply database migrations |
| `npm run seed` | Insert or refresh demo data |
| `npm run setup` | Migrate and seed |
| `npm test` | Run API integration tests |
| `npm run typecheck` | Type-check without emitting |
| `npm run db:start` | Start the local cluster on port 5433 |
| `npm run db:stop` | Stop the local cluster |
| `flutter analyze` | Static analysis |
| `flutter test` | Flutter unit tests |
| `flutter build apk --release --split-per-abi` | Build release APKs |

## 10. Troubleshooting

### The phone cannot reach the API

- Confirm the API is running: `Invoke-RestMethod http://localhost:3000/health`.
- Confirm the phone and computer are on the same Wi-Fi network.
- Use the computer's current LAN IPv4 address, not `localhost`.
- Allow Node.js through Windows Firewall when prompted, including the Public profile if
  the Wi-Fi network is classified as Public.
- Test from the computer:
  ```powershell
  Test-NetConnection <LAN-IP> -Port 3000
  ```
- If the Wi-Fi address changed, update it in the app.

### Login fails with a network error

The API address is wrong, the server is stopped, or the firewall is blocking port 3000.
Use the server-address button on the login screen.

### PostgreSQL will not start

- Check for an existing cluster using port 5433.
- Read `.pgdata\server.log`.
- Confirm `PG_BIN` points to the correct PostgreSQL version.
- If the cluster is corrupt and contains only demo data, recreate it with
  `db-init.ps1` as described above.

### API tests fail to connect

Tests use `TEST_DATABASE_URL` and expect `eventflow_test` to exist. Start the local cluster
and run `npm test` again. Do not point tests at a database containing data you need.

### Camera scanning does not start

- Grant camera permission when Android asks.
- Some emulators have no working camera; use **Manual check-in** with the short code.
- The login screen and manual form remain usable if the camera cannot start.

### Emulator will not boot

The Android emulator requires hardware acceleration. Install the Android Emulator
Hypervisor Driver (AEHD) or enable Windows Hypervisor Platform, then restart the emulator.
On machines where virtualization is unavailable, use a physical Android phone.

### A ticket says already used

Each ticket token is single-use. The first successful scan marks it used. If this was a
mistake, the current demo does not provide an undo action; reset the development database
or create a new booking.

## 11. Security and production notes

This project is configured for a local demo:

- PostgreSQL uses trust authentication and port 5433.
- Payment confirmation is simulated in the app and API.
- API secrets fall back to development values if not supplied.
- Release APKs are signed with the Android debug key.
- CORS is open by default for local development.
- The admin API exposes user and event management endpoints without a separate
  administration UI.

Before production use:

1. Use a managed PostgreSQL instance with strong authentication and TLS.
2. Replace JWT and ticket secrets with secret-manager values.
3. Replace the simulated payment adapter with a real provider and verify webhooks.
4. Add rate limiting, structured logging, and alerting.
5. Configure a private release keystore and Play Store signing.
6. Restrict CORS to known origins.
7. Add backup, restore, and database migration procedures.
