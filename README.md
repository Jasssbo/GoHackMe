# GoHackMe `v0.4.3`

A cyberpunk/hacking-themed multiplayer Go variant for mobile and desktop.
Players conquer subnets and launch cyberattacks on opponents' territory — wrapped in a neon-noir aesthetic inspired by *Serial Experiments Lain* and BitBurner's IPvGO minigame.

## Monorepo layout

```
app/          – Flutter app (mobile & desktop)
packages/
  go_engine/  – Pure Dart game engine (shared by app and server)
server/       – Dart Shelf WebSocket game server (Docker-ready)
scripts/      – Build and helper scripts
docs/         – Public privacy policy and web documentation
```

## Game modes

| Mode | How it works |
|---|---|
| **Solo** | Play against the built-in bot locally. No network required. |
| **LAN** | Host and guests connect over Wi-Fi/Ethernet on the same subnet. Rooms are auto-discovered via UDP beacon. |
| **The Wired** | Internet multiplayer through a self-hosted Dart WebSocket server (Render.com or any Docker host). Guests browse open rooms or enter a 6-character code. |

## How internet multiplayer works (The Wired)

The Wired mode is **server-authoritative WebSocket multiplayer** — no peer-to-peer, no WebRTC, no third-party signaling service.

```
App ──WebSocket──► Dart server (Render.com)
                        │
                        ├── validates every move via GameEngine
                        ├── broadcasts GameState to all players in room
                        └── exposes GET /rooms for the lobby browser
```

**Flow for a host:**
1. Taps **Host** → app generates a 6-char room code and opens a WebSocket to the server sending `joinRoom`.
2. The waiting room immediately shows **WAKING UP SERVER…** (Render.com cold-start detection), then **CONNECTING TO SERVER…** once the socket handshake succeeds, then the waiting room.
3. Once ≥ 2 players have joined the host can tap **START GAME** (or the room auto-starts when full).

**Flow for a guest:**
1. Taps **Join** → app fetches `GET /rooms` and shows a live-refreshing list of open rooms.
2. Guest can tap **JOIN** next to any room, or type a code manually.
3. After joining the guest waits for the host to start.

The server URL is injected at build time:
```bash
flutter run -d linux --dart-define=WIRED_SERVER_URL=https://your-app.onrender.com
```

## Privacy, Security & Zero-Telemetry TOS

GoHackMe strictly follows a **Zero-Data Privacy Protocol**:

- **No Third-Party Services or APIs**: Zero third-party web services, analytics SDKs, advertising trackers, or external IP geolocation APIs (e.g. no ip-api.com / ipapi.co pings) are bundled or contacted.
- **No Telemetry or Tracking**: No user telemetry, device metrics, or advertising identifiers (IDFA/GAID) are collected, stored, or sent.
- **Local Device Storage**: All game saves, settings, and node origin locations remain strictly on your local device.
- **Transient RAM-Only Session Data**: In Wired multiplayer mode, transient room data (display name and self-reported country node location) is held in server RAM only and automatically purged after 2 hours of inactivity.

## Quick start

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) ≥ 3.5
- Git
- Android SDK / Android Studio (if targeting Android)
- Linux desktop deps:
  ```bash
  sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev lld-18
  ```

### Clone & bootstrap

```bash
git clone https://github.com/Jasssbo/GoHackMe.git
cd GoHackMe  # (rename folder to match repo, or use your local name)

cd app && flutter pub get && cd ..
cd packages/go_engine && dart pub get && cd ../..
cd server && dart pub get && cd ..
```

> **Android signing:** `key.properties` is not committed. Copy
> `app/android/key.properties.template` → `app/android/key.properties` and fill
> in your keystore details for signed release builds. Debug builds work without it.

### Run the server locally

```bash
cd server
dart run bin/server.dart
# Listens on ws://0.0.0.0:8080/ws  and  http://0.0.0.0:8080/rooms
```

### Run the app

```bash
cd app

# Without a Wired server (LAN + Solo modes only)
flutter run -d linux

# With a local Wired server
flutter run -d linux --dart-define=WIRED_SERVER_URL=http://localhost:8080

# With the production server on Render.com
flutter run -d android --dart-define=WIRED_SERVER_URL=https://your-app.onrender.com
```

## Deploying the server

### Docker (local / any VPS)

```bash
# From the repo root
docker build -t gohackme-server .
docker run -p 8080:8080 gohackme-server
```

### Render.com (recommended)

1. Push the repo to GitHub.
2. On Render → **New Web Service** → connect the repository.
3. Set **Root Directory** to `/` (the Dockerfile is at the repo root).
4. Environment: Docker. Port: `8080`.
5. Deploy. Copy the `https://your-app.onrender.com` URL.
6. Build the app with `--dart-define=WIRED_SERVER_URL=https://your-app.onrender.com`.

The `Dockerfile` at the repo root is a two-stage build:
- Stage 1: compiles the Dart server AOT binary inside `dart:stable`.
- Stage 2: copies the binary into a minimal `debian:bookworm-slim` image.

## Building for release

```bash
cd app

# Android App Bundle
flutter build appbundle --release --dart-define=WIRED_SERVER_URL=https://...

# Universal APK
flutter build apk --release --dart-define=WIRED_SERVER_URL=https://...

# Linux desktop
flutter build linux --release --dart-define=WIRED_SERVER_URL=https://...

# Linux AppImage (after flutter build linux)
cd .. && ./scripts/build_appimage.sh --skip-build
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

## Architecture overview

- **`go_engine`** — pure Dart, zero Flutter deps. Go rules (superko, area scoring), the attack system, and the shared `GameMessage` wire protocol.
- **`server`** — server-authoritative Shelf/WebSocket server. Validates every move via `GameEngine`, broadcasts full `GameState` snapshots, manages rooms. Runs in Docker.
- **`app`** — Flutter with Riverpod state management, go_router navigation, and a custom cyberpunk theme.

## Security & Privacy Highlights

The internet-facing server (Wired mode) applies defence-in-depth:

| Layer | Detail |
|---|---|
| **Transport** | TLS 1.3 + AES-256-GCM on all connections (`wss://`) |
| **Telemetry & Trackers** | **Zero** telemetry, zero advertising SDKs, zero external third-party API pings |
| **Connection & room limits** | Server-side caps on concurrent connections and active rooms |
| **Message size** | Hard cap per message on both WebSocket and LAN TCP channels |
| **Rate limiting** | Per-connection WebSocket and per-IP HTTP rate limits enforced |
| **Input validation** | All identifiers & coordinates validated, clamped, and sanitised before touching game logic |
| **Identity** | Server-verified player identity on all game actions — client cannot spoof |
| **Headers** | `X-Content-Type-Options`, `Strict-Transport-Security`, `Cache-Control: no-store` |
| **Secrets** | Server URL injected at compile time (`--dart-define`); keystore excluded via `.gitignore` |

LAN mode runs on a trusted local network. Rooms are protected against UDP beacon spoofing via authenticated beacon signatures.

## License

[MIT](LICENSE)

