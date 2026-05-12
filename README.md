# GoHackMe

A cyberpunk/hacking-themed online multiplayer Go variant for mobile and desktop. Players conquers subnets and launch attacks on opponents' territory — all wrapped in a neon-noir aesthetic. Inspired by Lain Serial Experiment and BitBurner "IPvGO" minigame.

## Monorepo layout

```
app/          – Flutter app (mobile & desktop)
packages/
  go_engine/  – Pure Dart game engine (shared by app and server)
server/       – Dart Shelf WebSocket game server (Docker-ready)
scripts/      – Python code-generation helpers
```

## Quick start

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) ≥ 3.5 (includes the Dart SDK)
- Git
- Android SDK / Android Studio if targeting Android
- For Linux desktop: `clang`, `cmake`, `ninja-build`, `libgtk-3-dev`
  ```bash
  sudo apt install clang cmake ninja-build libgtk-3-dev
  ```

### Clone & bootstrap

```bash
git clone https://github.com/Jasssbo/GoHackMe_Flutter.git
cd GoHackMe_Flutter

# Install dependencies for all packages
cd app && flutter pub get && cd ..
cd packages/go_engine && dart pub get && cd ../..
cd server && dart pub get && cd ..
```

> **Note for contributors** — `key.properties` (Android signing) is intentionally not committed.
> Copy `app/android/key.properties.template` → `app/android/key.properties` and fill in your
> keystore details if you need to produce a signed release build. Debug builds work without it.

### Run the server (local)

```bash
cd server
dart run bin/server.dart
# Server listens on ws://0.0.0.0:8080/ws
```

### Run the app

```bash
cd app
flutter run                    # pick a connected device interactively
flutter run -d linux           # Linux desktop
flutter run -d android         # Android (device or emulator)
```

## Building for release

```bash
cd app

# Android App Bundle (Google Play)
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab

# Universal APK (sideload / testing)
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk

# Linux desktop
flutter build linux --release
# → build/linux/x64/release/bundle/

# Linux AppImage (after flutter build linux)
cd ..
./scripts/build_appimage.sh --skip-build
# → build/GoHackMe-x86_64.AppImage
```

## Running tests

```bash
# Engine unit tests
cd packages/go_engine && dart test

# App widget tests
cd app && flutter test

# Server tests
cd server && dart test
```

## Architecture

- **Game engine** (`go_engine`): pure Dart, zero Flutter dependencies. Implements Go rules (superko, area scoring), the attack system, and the shared WebSocket message protocol.
- **Server** (`gohackme_server`): server-authoritative Shelf server. Validates every move, broadcasts state, manages rooms. Runs in Docker.
- **App** (`gohackme`): Flutter with Riverpod state management, go_router navigation, and a custom `CyberpunkTheme`.

## Deployment (server)

```bash
cd server
docker build -t gohackme-server .
docker run -p 8080:8080 gohackme-server
```

See `server/README.md` for full deployment notes including TLS / reverse-proxy setup.

## License

[GNU-GPLv3](LICENSE)
