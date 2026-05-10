import 'dart:async';

import 'package:go_engine/go_engine.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Manages the WebSocket connection to the GoHackMe server.
///
/// [GameSyncService] is the single point of truth for the network layer.
/// It exposes:
///   - [connect] to open the WebSocket and join a room
///   - [gameStateStream] for authoritative [GameState] updates
///   - [logStream] for terminal-style log messages from the server
///   - [send] to push actions to the server
class GameSyncService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  final _gameStateController = StreamController<GameState>.broadcast();
  final _logController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<GameState> get gameStateStream => _gameStateController.stream;
  Stream<String> get logStream => _logController.stream;
  Stream<String> get errorStream => _errorController.stream;

  bool get isConnected => _channel != null;

  // ── Connect ───────────────────────────────────────────────────────────────

  Future<void> connect({
    required String serverUrl,
    required String playerId,
    required String roomId,
    required String displayName,
    int boardSize = 19,
    int maxPlayers = 2,
  }) async {
    await dispose();

    // OWASP A01: validate URL scheme before connecting to prevent accidental
    // connections to non-WS schemes (file://, javascript://, etc.).
    final uri = Uri.tryParse(serverUrl);
    if (uri == null ||
        (uri.scheme != 'ws' && uri.scheme != 'wss') ||
        uri.host.isEmpty) {
      _errorController.add('INVALID_SERVER_URL: must start with ws:// or wss://');
      return;
    }

    _channel = WebSocketChannel.connect(uri);
    await _channel!.ready;

    _sub = _channel!.stream.listen(
      (raw) => _handleMessage(raw as String),
      onDone: () => _logController.add('DISCONNECTED'),
      onError: (e) => _errorController.add('WS_ERROR: $e'),
      cancelOnError: false,
    );

    // Join the room immediately after connecting
    send(GameMessage.joinRoom(
      playerId: playerId,
      roomId: roomId,
      displayName: displayName,
      boardSize: boardSize,
      maxPlayers: maxPlayers,
    ));
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  void send(GameMessage message) {
    _channel?.sink.add(message.toJsonString());
  }

  // ── Incoming message handler ──────────────────────────────────────────────

  void _handleMessage(String raw) {
    GameMessage message;
    try {
      message = GameMessage.fromJsonString(raw);
    } catch (_) {
      _logController.add('PARSE_ERROR: $raw');
      return;
    }

    switch (message.type) {
      case MessageType.gameStateUpdate:
        final stateJson = message.payload['state'];
        if (stateJson is Map<String, dynamic>) {
          try {
            final gs = GameState.fromJson(stateJson);
            _gameStateController.add(gs);
          } catch (e) {
            _logController.add('STATE_PARSE_ERROR: $e');
          }
        }
        final log = message.payload['log'] as String?;
        if (log != null) _logController.add(log);

      case MessageType.error:
        final reason = message.payload['reason'] as String? ?? 'UNKNOWN_ERROR';
        _errorController.add(reason);
        _logController.add('ERROR: $reason');

      case MessageType.playerJoined:
        final name = (message.payload['player']
                as Map<String, dynamic>?)?['displayName'] ??
            '?';
        _logController.add('PLAYER_JOINED: $name');

      case MessageType.playerLeft:
        _logController.add('PLAYER_LEFT: ${message.payload['playerId']}');

      case MessageType.gameOver:
        _logController.add('GAME_OVER');

      case MessageType.pong:
        break; // heartbeat, ignore

      default:
        _logController.add('MSG: ${message.type.name}');
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _sub = null;
  }
}
