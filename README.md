# GoHackMe

A cyberpunk/hacking-themed online multiplayer Go variant for mobile and desktop. Players place stones, earn subnets, and launch attacks on opponents' territory — all wrapped in a neon-noir aesthetic.

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
- [Flutter SDK](https://flutter.dev/docs/get-started/install) ≥ 3.5
- [Dart SDK](https://dart.dev/get-dart) ≥ 3.5
- [Melos](https://melos.dev) (`dart pub global activate melos`)

### Bootstrap

```bash
melos bootstrap   # installs dependencies in all packages
```

### Run the server (local)

```bash
cd server
dart run bin/server.dart
# Server listens on ws://0.0.0.0:8080/ws
```

### Run the app

```bash
cd app
flutter run
```

## Running tests

```bash
melos test        # runs all tests across all packages
# or in a specific package:
cd packages/go_engine && dart test
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
