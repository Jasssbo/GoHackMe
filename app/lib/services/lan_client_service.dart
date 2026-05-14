import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:go_engine/go_engine.dart';

import 'i_game_transport.dart';
import 'lan_player.dart';

// ── LanClientService ───────────────────────────────────────────────────────────────

/// Connects to a LAN host over TCP and exchanges [GameMessage] JSON lines.
///
/// After calling [connect], the caller should listen on [stateStream] for
/// authoritative [GameState] updates and use [sendAction] to dispatch player
/// actions.
class LanClientService implements IGameTransport {
  Socket? _socket;
  final StringBuffer _buf = StringBuffer();

  // ── Keepalive ────────────────────────────────────────────────────────────
  Timer? _pingTimer;
  DateTime _lastPong = DateTime.now();
  static const _kPingInterval = Duration(seconds: 5);
  static const _kPingTimeout = Duration(seconds: 15);

  final StreamController<GameState> _stateCtrl =
      StreamController<GameState>.broadcast();
  final StreamController<String> _logCtrl = StreamController<String>.broadcast();
  final StreamController<String> _errorCtrl = StreamController<String>.broadcast();
  final StreamController<List<LanPlayer>> _playersCtrl =
      StreamController<List<LanPlayer>>.broadcast();

  final List<LanPlayer> _players = [];

  @override
  Stream<GameState> get stateStream => _stateCtrl.stream;
  @override
  Stream<String> get logStream => _logCtrl.stream;
  @override
  Stream<String> get errorStream => _errorCtrl.stream;
  @override
  Stream<List<LanPlayer>> get playerListStream => _playersCtrl.stream;

  bool get isConnected => _socket != null;

  // ── Connect ───────────────────────────────────────────────────────────────

  Future<void> connect({
    required InternetAddress hostAddress,
    required int tcpPort,
    required String playerId,
    required String displayName,
    required String roomCode,
  }) async {
    // Close any existing socket without touching the stream controllers.
    // The provider always creates a fresh LanClientService before calling
    // connect(), so controllers are already open and subscriptions are already
    // attached — destroying them here would break those subscriptions.
    if (_socket != null) {
      await _socket!.close();
      _socket = null;
    }
    _buf.clear();
    _players.clear();

    _socket = await Socket.connect(hostAddress, tcpPort,
        timeout: const Duration(seconds: 5));

    _socket!.listen(
      _onData,
      onDone: () {
        _logCtrl.add('DISCONNECTED');
        _errorCtrl.add('HOST_DISCONNECTED');
      },
      onError: (e) => _errorCtrl.add('TCP_ERROR: $e'),
      cancelOnError: false,
    );

    // Introduce ourselves
    sendAction(GameMessage.joinRoom(
      playerId: playerId,
      roomId: roomCode,
      displayName: displayName,
    ));

    // Seed the local player list with ourselves.
    _players.add(LanPlayer(id: playerId, displayName: displayName));
    _playersCtrl.add(List.unmodifiable(_players));

    // Start keepalive — send ping every 5 s, error out if host goes silent.
    _lastPong = DateTime.now();
    _pingTimer = Timer.periodic(_kPingInterval, (_) {
      if (DateTime.now().difference(_lastPong) > _kPingTimeout) {
        _errorCtrl.add('HOST_TIMEOUT');
        dispose();
        return;
      }
      sendAction(GameMessage.ping());
    });
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  @override
  void sendAction(GameMessage msg) {
    try {
      _socket?.write('${msg.toJsonString()}\n');
      _socket?.flush();
    } catch (e) {
      _errorCtrl.add('SEND_ERROR: $e');
    }
  }

  // ── Incoming data ─────────────────────────────────────────────────────────

  void _onData(List<int> data) {
    _buf.write(utf8.decode(data, allowMalformed: true));
    final raw = _buf.toString();
    final lines = raw.split('\n');
    _buf.clear();
    if (lines.isNotEmpty) _buf.write(lines.last);

    for (final line in lines.take(lines.length - 1)) {
      if (line.trim().isEmpty) continue;
      _handleLine(line);
    }
  }

  void _handleLine(String line) {
    GameMessage msg;
    try {
      msg = GameMessage.fromJsonString(line);
    } catch (_) {
      return;
    }

    switch (msg.type) {
      case MessageType.ping:
        // Host is checking we are alive — reply immediately.
        sendAction(GameMessage.pong());

      case MessageType.pong:
        _lastPong = DateTime.now();

      case MessageType.gameStateUpdate:
        final stateJson = msg.payload['state'];
        if (stateJson is Map<String, dynamic>) {
          try {
            _stateCtrl.add(GameState.fromJson(stateJson));
          } catch (e) {
            _logCtrl.add('STATE_PARSE_ERROR: $e');
          }
        }
        final log = msg.payload['log'] as String?;
        if (log != null && log.isNotEmpty) _logCtrl.add(log);

      case MessageType.error:
        final reason =
            msg.payload['reason'] as String? ?? 'UNKNOWN_ERROR';
        _errorCtrl.add(reason);
        _logCtrl.add('ERROR: $reason');

      case MessageType.playerJoined:
        final player = msg.payload['player'] as Map<String, dynamic>?;
        if (player != null) {
          final id = player['id'] as String? ?? '';
          final name = player['displayName'] as String? ?? '?';
          if (id.isNotEmpty && _players.every((p) => p.id != id)) {
            _players.add(LanPlayer(id: id, displayName: name));
            _playersCtrl.add(List.unmodifiable(_players));
          }
          _logCtrl.add('PLAYER_JOINED: $name');
        }

      case MessageType.playerLeft:
        final id = msg.payload['playerId'] as String? ?? '';
        _players.removeWhere((p) => p.id == id);
        _playersCtrl.add(List.unmodifiable(_players));
        _logCtrl.add('PLAYER_LEFT: $id');

      case MessageType.gameOver:
        _logCtrl.add('GAME_OVER');

      default:
        break;
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    await _socket?.close();
    _socket = null;
    _buf.clear();
    _players.clear();
    await _stateCtrl.close();
    await _logCtrl.close();
    await _errorCtrl.close();
    await _playersCtrl.close();
  }
}
