# EventFlow mobile

Flutter Android client for the EventFlow ticketing platform.

Features include event discovery, ticket reservation, simulated mobile-money checkout,
QR tickets, offline ticket access, organizer sales dashboards, and camera or short-code
check-in.

## Run

```powershell
flutter pub get
flutter run
```

The API must be running and reachable from the phone or emulator. Set the server address
from the login screen or Profile, or pass it at build time:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

## Build

```powershell
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

See [`../docs/SETUP.md`](../docs/SETUP.md) for the full backend, database, network, and
troubleshooting guide.
