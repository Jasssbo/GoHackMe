/// GoHackMe – shared Go game engine.
///
/// Import this barrel in both the Flutter app and the Dart server.
/// Contains no Flutter dependency; pure Dart only.
library;

// ── Models ──────────────────────────────────────────────────────────────────
export 'src/models/position.dart';
export 'src/models/stone_color.dart';
export 'src/models/board.dart';
export 'src/models/attack.dart';
export 'src/models/game_state.dart';
export 'src/models/player.dart';

// ── Engine ───────────────────────────────────────────────────────────────────
export 'src/engine/go_rules.dart';
export 'src/engine/scorer.dart';
export 'src/engine/attack_system.dart';
export 'src/engine/game_engine.dart';
export 'src/engine/game_event.dart';
export 'src/engine/bot_player.dart';

// ── Messages (shared client↔server protocol) ────────────────────────────────
export 'src/messages/game_message.dart';
