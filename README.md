# EventFlow

EventFlow is a full-stack event ticketing app for discovering events, reserving tickets,
paying with a simulated mobile-money provider, receiving QR tickets, and checking attendees
in at the gate.

- **Mobile:** Flutter 3 / Dart 3, Android
- **API:** Node.js, Express 5, TypeScript, Zod
- **Database:** PostgreSQL 18
- **Auth:** JWT with bcrypt password hashing
- **Tickets:** HMAC-signed QR tokens, hashed at rest, plus short check-in codes
- **Payments:** Simulated MTN / Airtel / Zamtel mobile-money flow with idempotent confirmation

## Features

### Attendees
- Browse and search published events
- View event details, ticket types, prices, and availability
- Reserve tickets with a 15-minute payment hold
- Pay through a simulated mobile-money prompt
- View QR tickets and short codes
- Keep tickets available offline after they have been loaded once
- Cancel confirmed or pending bookings

### Organizers
- Create draft events and ticket types
- Publish or cancel events
- View sales, revenue, bookings, and check-in progress
- Scan attendee QR codes with the phone camera
- Check attendees in with an 8-character short code
- View attendee lists

### Admins and super admins
- Use organizer features across all events
- View platform statistics in the Profile tab
- Super admins get a server-rendered web control room at `/admin`
- Manage user roles, cancel events, review bookings, and inspect the audit log
- Dashboard access uses a signed session cookie with CSRF protection and rate-limited sign-in

## Repository layout

```text
eventflow/
  api/                 Express + TypeScript API
    src/
      routes/          Auth, events, bookings, payments, tickets, admin API and web dashboard
      admin/           Dashboard session, CSRF, audit, and path helpers
      services/        Booking, payment, event, and ticket logic
      db/              Connection, migration runner, schema
      scripts/         Migrate and seed commands
    views/admin/       EJS dashboard templates
    public/admin/      Dashboard stylesheet
    tests/             API integration tests
  mobile/              Flutter Android app
    lib/
      screens/         Attendee, organizer, scanning, and profile screens
      models.dart      API models and formatting
      api_client.dart  HTTP client
      auth_state.dart  Session, API URL, and offline user cache
      ticket_cache.dart
  scripts/             Local PostgreSQL lifecycle scripts
  docs/SETUP.md        Detailed setup and troubleshooting
```

## Quick start (Windows PowerShell)

### 1. Prerequisites

- Node.js 20 or newer
- PostgreSQL 18 installed (default path: `C:\Program Files\PostgreSQL\18\bin`)
- Flutter 3.47 or newer with the Android toolchain configured
- Android SDK / platform tools for building and installing the APK

### 2. Install and configure the backend

```powershell
cd api
npm install
Copy-Item .env.example .env
```

Edit `api\.env` and replace `JWT_SECRET` and `TICKET_SECRET` with long random values.

### 3. Create and start the local database

The project uses an isolated development cluster in `.pgdata` on port **5433**, so it does
not touch an existing PostgreSQL service on port 5432.

```powershell
# From the repository root
.\scripts\db-init.ps1    # first time only: creates the cluster and databases
.\scripts\db-start.ps1
```

Or, from `api`:

```powershell
npm run db:start
npm run db:stop
```

### 4. Migrate, seed, and run the API

```powershell
cd api
npm run setup            # migrations + demo data
npm run dev              # development server with watch mode
```

For a compiled server instead:

```powershell
npm run build
npm start
```

The API listens on `0.0.0.0:3000`.

```powershell
Invoke-RestMethod http://localhost:3000/health
```

The super admin dashboard is available at `http://localhost:3000/admin`.

### 5. Run the mobile app

```powershell
cd mobile
flutter pub get
flutter run
```

To build installable APKs:

```powershell
flutter build apk --debug
flutter build apk --release --split-per-abi
```

APK output:

```text
mobile\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
mobile\build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk
mobile\build\app\outputs\flutter-apk\app-x86_64-release.apk
```

Install on a connected phone:

```powershell
& "C:\Android\Sdk\platform-tools\adb.exe" install -r "mobile\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
```

## Demo accounts

All demo accounts use the password `Password123!`.

| Role | Email |
| --- | --- |
| Attendee | `attendee@eventflow.zm` |
| Organizer | `organizer@eventflow.zm` |
| Admin | `admin@eventflow.zm` |
| Super admin | `superadmin@eventflow.zm` |

The attendee account starts with a confirmed booking and two QR tickets for the seeded
Lusaka Live Concert. The super admin account is the only demo account that can sign in at
`/admin`.

## Mobile API address

The app must reach the API over the network. Use the server-address button on the login
screen or the API setting in Profile to change it.

- **Physical phone:** use the computer's Wi-Fi IPv4 address, for example
  `http://172.19.25.191:3000`. The phone and computer must be on the same network.
- **Android emulator:** use `http://10.0.2.2:3000`, which maps to the host machine.
- **USB with adb reverse:** run `adb reverse tcp:3000 tcp:3000`, then use
  `http://127.0.0.1:3000`.

The current build defaults to `http://172.19.25.191:3000`. If your Wi-Fi address changes,
update it in the app or rebuild with:

```powershell
flutter build apk --release --split-per-abi --dart-define=API_BASE_URL=http://YOUR_IP:3000
```

A server address saved in the app takes precedence over the compiled default.

## Tests

```powershell
cd api
npm run typecheck
npm test
```

The API suite covers concurrent booking limits, idempotency, hold expiry, ticket scanning,
dashboard authentication, CSRF rejection, role changes, event cancellation, and audit logs.

```powershell
cd mobile
flutter analyze
flutter test
```

## Demo flow

1. Log in as the attendee and open **Discover**.
2. Open an event, select tickets, and reserve them.
3. On **Checkout**, pay with any valid-looking phone number and tap **Approve in demo**.
4. Open **Tickets** and show the QR code or short code.
5. Log out, log in as the organizer, open **My events**, and tap **Scan**.
6. Scan the attendee's QR code, or enter the short code under **Manual check-in**.
7. The first scan succeeds; scanning the same ticket again reports that it was already used.
8. Open `http://localhost:3000/admin`, sign in as `superadmin@eventflow.zm`, and review
   users, events, bookings, and the audit log.

## More documentation

See [`docs/SETUP.md`](docs/SETUP.md) for prerequisites, database lifecycle commands,
network setup, troubleshooting, and security notes.
