#!/usr/bin/env python3
"""Writes all pubspec.yaml files for the GoHackMe monorepo."""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def write(path, content):
    full_path = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full_path), exist_ok=True)
    with open(full_path, "w") as f:
        f.write(content)
    print(f"  wrote {path}")


# ─── go_engine ──────────────────────────────────────────────────────────────
write(
    "packages/go_engine/pubspec.yaml",
    """\
name: go_engine
description: >-
  Pure-Dart Go game engine shared between the Flutter app and the Dart server.
  Implements board logic, Go rules (capture, Ko, scoring), the subnet economy,
  and the attack mechanics for GoHackMe.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.5.0

dependencies:
  collection: ^1.18.0

dev_dependencies:
  lints: ^5.0.0
  test: ^1.24.0
""",
)

# ─── server ──────────────────────────────────────────────────────────────────
write(
    "server/pubspec.yaml",
    """\
name: gohackme_server
description: >-
  GoHackMe WebSocket game server. Runs the authoritative go_engine
  and broadcasts state to all connected players via shelf + WebSockets.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.5.0

dependencies:
  shelf: ^1.4.2
  shelf_web_socket: ^3.0.0
  shelf_router: ^1.1.4
  uuid: ^4.5.1
  go_engine:
    path: ../packages/go_engine

dev_dependencies:
  lints: ^5.0.0
  test: ^1.24.0
""",
)

# ─── app ─────────────────────────────────────────────────────────────────────
write(
    "app/pubspec.yaml",
    """\
name: gohackme
description: >-
  GoHackMe – a cyberpunk/hacking-themed online multiplayer Go variant for
  mobile and desktop. Place stones, gain subnets, launch attacks.
version: 1.0.0+1
publish_to: none

environment:
  sdk: ^3.5.0

dependencies:
  flutter:
    sdk: flutter

  # State management
  flutter_riverpod: ^2.6.1
  riverpod_annotation: ^2.6.1

  # Navigation
  go_router: ^14.8.1

  # Networking
  web_socket_channel: ^3.0.2

  # Serialisation
  freezed_annotation: ^2.4.4
  json_annotation: ^4.9.0

  # UI
  google_fonts: ^6.2.1
  flutter_animate: ^4.5.2

  # Storage / misc
  shared_preferences: ^2.3.4
  uuid: ^4.5.1

  # Shared game logic
  go_engine:
    path: ../packages/go_engine

flutter:
  uses-material-design: true
  assets:
    - assets/shaders/
    - assets/fonts/
    - assets/images/

dev_dependencies:
  flutter_test:
    sdk: flutter

  # Code generation
  riverpod_generator: ^2.6.3
  build_runner: ^2.4.13
  freezed: ^2.5.7
  json_serializable: ^6.8.0
  custom_lint: ^0.7.4
  riverpod_lint: ^2.4.3
  flutter_lints: ^5.0.0
""",
)

print("All pubspec.yaml files written successfully.")
