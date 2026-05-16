import 'package:go_engine/go_engine.dart';

import 'connected_player.dart';

/// Abstraction over all multiplayer transport implementations.
///
/// [LanHostService], [LanClientService], and [WiredServerService] all implement
/// this interface so that game notifiers can work with any transport without
/// branching on role or network type.
abstract interface class IGameTransport {
  Stream<GameState> get stateStream;
  Stream<String> get logStream;

  /// Emits transport-level errors (e.g. host disconnected).
  /// Host implementations may return a stream that never emits.
  Stream<String> get errorStream;

  Stream<List<ConnectedPlayer>> get playerListStream;

  /// Dispatches a player game-action message.
  ///
  /// For the host this applies the action directly to the engine; for a
  /// client it forwards the message over TCP.
  void sendAction(GameMessage msg);

  Future<void> dispose();
}
