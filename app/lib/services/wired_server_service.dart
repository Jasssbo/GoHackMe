import 'dart:async';
import 'dart:convert';

import 'package:go_engine/go_engine.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/config/app_config.dart';
import 'i_game_transport.dart';
import 'connected_player.dart';

// ── WiredRoomInfo ─────────────────────────────────────────────────────────

/// A room visible in the Wired lobby browser.
class WiredRoomInfo {
  final String code;
  final int boardSize;
  final int playerCount;
  final int maxPlayers;
  final double? lat;
  final double? lon;
  final String? city;
  final String? country;
  /// True when the game has already started but a player disconnected within
  /// their 30-second reconnect grace window — shown so they can rejoin.
  final bool reconnecting;

  const WiredRoomInfo({
    required this.code,
    required this.boardSize,
    required this.playerCount,
    required this.maxPlayers,
    this.lat,
    this.lon,
    this.city,
    this.country,
    this.reconnecting = false,
  });

  factory WiredRoomInfo.fromJson(Map<String, dynamic> j) => WiredRoomInfo(
        code: j['code'] as String,
        boardSize: j['boardSize'] as int,
        playerCount: j['playerCount'] as int,
        maxPlayers: j['maxPlayers'] as int,
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
        city: j['city'] as String?,
        country: j['country'] as String?,
        reconnecting: j['reconnecting'] as bool? ?? false,
      );
}

// ── WiredServerService ────────────────────────────────────────────────────

/// WebSocket client for internet ("Wired") multiplayer.
///
/// Connects to the public Render.com server (URL injected at compile time via
/// `--dart-define=WIRED_SERVER_URL=https://...`) and implements [IGameTransport]
/// so [WiredGameNotifier] can treat it like any other transport.
///
/// Player list is tracked by listening to [MessageType.playerJoined] /
/// [MessageType.playerLeft] server broadcasts.
class WiredServerService implements IGameTransport {
  static const _kMaxReconnectAttempts = 5;
  /// Number of cold-start wake retries before giving up with CONNECTION_FAILED.
  static const _kMaxWakeAttempts = 8;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _disposed = false;
  int _reconnectAttempts = 0;
  int _wakeAttempts = 0;
  /// True once the socket has successfully connected at least once.  Used to
  /// distinguish an initial cold-start from a mid-game reconnect attempt.
  bool _hasConnectedOnce = false;

  // Stored for reconnection
  String? _playerId;
  String? _displayName;
  String? _roomCode;
  int _boardSize = 19;
  int _maxPlayers = 2;

  final _stateCtrl = StreamController<GameState>.broadcast();
  final _logCtrl = StreamController<String>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();
  final _playersCtrl = StreamController<List<ConnectedPlayer>>.broadcast();
  final _players = <ConnectedPlayer>[];

  @override
  Stream<GameState> get stateStream => _stateCtrl.stream;
  @override
  Stream<String> get logStream => _logCtrl.stream;
  @override
  Stream<String> get errorStream => _errorCtrl.stream;
  @override
  Stream<List<ConnectedPlayer>> get playerListStream => _playersCtrl.stream;

  // ── Connection ────────────────────────────────────────────────────────────

  Future<void> connect({
    required String playerId,
    required String displayName,
    required String roomCode,
    int boardSize = 19,
    int maxPlayers = 2,
  }) async {
    _playerId = playerId;
    _displayName = displayName;
    _roomCode = roomCode;
    _boardSize = boardSize;
    _maxPlayers = maxPlayers;
    await _openSocket();
  }

  Future<void> _openSocket() async {
    final base = AppConfig.wiredServerUrl;
    // Convert http(s):// → ws(s):// using Uri to avoid fragile string replacements.
    final baseUri = Uri.tryParse(base);
    if (baseUri == null) {
      _errorCtrl.add('INVALID_SERVER_URL');
      return;
    }
    final wsScheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
    final uri = baseUri.replace(scheme: wsScheme, path: '/ws');

    _channel = WebSocketChannel.connect(uri);
    try {
      await _channel!.ready.timeout(const Duration(seconds: 8));
    } catch (e) {
      await _channel?.sink.close();
      _channel = null;
      // Only show the "waking up" UX for the initial connection to a potentially
      // sleeping Render.com server.  Mid-game reconnects use the existing path.
      if (!_disposed && !_hasConnectedOnce && _wakeAttempts < _kMaxWakeAttempts) {
        _wakeAttempts++;
        _logCtrl.add('WAKE_ATTEMPT: $_wakeAttempts/$_kMaxWakeAttempts');
        _errorCtrl.add('WAKING_UP');
        Future.delayed(const Duration(seconds: 5), () {
          if (!_disposed) _openSocket();
        });
      } else {
        _errorCtrl.add('CONNECTION_FAILED');
      }
      return;
    }
    _hasConnectedOnce = true;
    _wakeAttempts = 0;

    _sub = _channel!.stream.listen(
      _handleMessage,
      onDone: _onDone,
      onError: _onWsError,
      cancelOnError: false,
    );

    // Announce ourselves; server creates the room if it doesn't exist.
    _channel!.sink.add(GameMessage.joinRoom(
      playerId: _playerId!,
      roomId: _roomCode!,
      displayName: _displayName!,
      boardSize: _boardSize,
      maxPlayers: _maxPlayers,
    ).toJsonString());

    _logCtrl.add('UPLINK_ESTABLISHED');
  }

  // ── Incoming messages ─────────────────────────────────────────────────────

  void _handleMessage(dynamic raw) {
    if (raw is! String) return;
    GameMessage msg;
    try {
      msg = GameMessage.fromJsonString(raw);
    } catch (_) {
      return;
    }

    switch (msg.type) {
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

      case MessageType.playerJoined:
        final p = msg.payload['player'] as Map<String, dynamic>?;
        if (p != null) {
          final player = ConnectedPlayer(
            id: p['id'] as String? ?? '',
            displayName: p['displayName'] as String? ?? '?',
          );
          if (!_players.any((e) => e.id == player.id)) {
            _players.add(player);
            _playersCtrl.add(List.from(_players));
          }
          _logCtrl.add('PLAYER_JOINED: ${player.displayName}');
        }

      case MessageType.playerLeft:
        final pid = msg.payload['playerId'] as String?;
        if (pid != null) {
          _players.removeWhere((p) => p.id == pid);
          _playersCtrl.add(List.from(_players));
          _logCtrl.add('PLAYER_LEFT: $pid');
        }

      case MessageType.error:
        final reason = msg.payload['reason'] as String? ?? 'UNKNOWN_ERROR';
        _errorCtrl.add(reason);
        _logCtrl.add('ERROR: $reason');

      case MessageType.gameOver:
        _logCtrl.add('GAME_OVER');

      case MessageType.chat:
        final senderName = msg.payload['senderName'] as String? ?? '?';
        final text = msg.payload['text'] as String? ?? '';
        // Emit with CHAT> prefix so the terminal widget can colour it.
        _logCtrl.add('CHAT>$senderName>$text');

      case MessageType.ping:
        _channel?.sink.add(GameMessage.pong().toJsonString());

      case MessageType.pong:
        break;

      default:
        break;
    }
  }

  void _onDone() {
    _logCtrl.add('DISCONNECTED');
    if (!_disposed) _scheduleReconnect();
  }

  void _onWsError(Object e) {
    _logCtrl.add('WS_ERROR: $e');
    if (!_disposed) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnectAttempts >= _kMaxReconnectAttempts) {
      _errorCtrl.add('SERVER_DISCONNECTED');
      return;
    }
    _reconnectAttempts++;
    _logCtrl
        .add('RECONNECT_ATTEMPT: $_reconnectAttempts/$_kMaxReconnectAttempts');
    Future.delayed(Duration(seconds: _reconnectAttempts * 3), () async {
      if (_disposed) return;
      try {
        await _sub?.cancel();
        await _channel?.sink.close();
        _channel = null;
        _sub = null;
        await _openSocket();
        _reconnectAttempts = 0;
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  @override
  void sendAction(GameMessage msg) {
    _channel?.sink.add(msg.toJsonString());
  }

  /// Sends a chat message to the current room.
  void sendChatMessage(String text) {
    final pid = _playerId;
    final room = _roomCode;
    if (pid == null || room == null) return;
    _channel?.sink.add(
      GameMessage.chat(playerId: pid, roomId: room, text: text).toJsonString(),
    );
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _sub = null;
    if (!_stateCtrl.isClosed) await _stateCtrl.close();
    if (!_logCtrl.isClosed) await _logCtrl.close();
    if (!_errorCtrl.isClosed) await _errorCtrl.close();
    if (!_playersCtrl.isClosed) await _playersCtrl.close();
  }

  // ── Static helpers ────────────────────────────────────────────────────────

  /// Fetches the list of open (not-started) rooms from the server.
  /// Used by the Wired lobby browser.
  static Future<List<WiredRoomInfo>> fetchOpenRooms() async {
    if (!AppConfig.isWiredConfigured) return const [];
    try {
      final resp = await http
          .get(Uri.parse('${AppConfig.wiredServerUrl}/rooms'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return const [];
      final list = jsonDecode(resp.body) as List<dynamic>;
      return list
          .map((e) => WiredRoomInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
