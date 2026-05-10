import 'package:go_engine/go_engine.dart';

import 'lan_player.dart';

/// Abstraction over the two LAN transport implementations (host + client).
///
/// [LanHostService] and [LanClientService] both implement this interface so
/// that [LanGameNotifier] can work with either without branching on role.
///
/// DIP: high-level policy ([LanGameNotifier]) depends on this abstraction,
/// not on concrete low-level details (TCP socket, applyHostAction, etc.).
abstract interface class IGameTransport {
  Stream<GameState> get stateStream;
  Stream<String> get logStream;

  /// Emits transport-level errors (e.g. host disconnected).
  /// Host implementations may return a stream that never emits.
  Stream<String> get errorStream;

  Stream<List<LanPlayer>> get playerListStream;

  /// Dispatches a player game-action message.
  ///
  /// For the host this applies the action directly to the engine; for a
  /// client it forwards the message over TCP.
  void sendAction(GameMessage msg);

  Future<void> dispose();
}
