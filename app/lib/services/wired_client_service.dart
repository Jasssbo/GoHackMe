import 'dart:async';
import 'dart:convert';

import 'package:go_engine/go_engine.dart';
import 'package:uuid/uuid.dart';

import 'i_game_transport.dart';
import 'lan_player.dart';
import 'webrtc_wired_service.dart';
import 'wired_relay_service.dart';

// ── WiredClientService ────────────────────────────────────────────────────

/// WebRTC client for "The Wired" mode.
///
/// Flow (guest-as-offerer):
///   1. Caller receives the host's 6-char room code.
///   2. [connectWithCode] creates a WebRTC offer and posts it to the shared
///      offer topic on the relay — the same topic all guests use.
///   3. The host's background poller picks up the offer, generates an answer,
///      and posts it to the per-session answer topic.
///   4. [WiredClientService] polls for its answer, completes the handshake,
///      and sends a [MessageType.joinRoom] message once the channel opens.
class WiredClientService implements IGameTransport {
  WiredPeerConnection? _conn;

  late String _playerId;
  late String _displayName;
  late String _roomCode;

  bool _disposed = false;
  int _reconnectAttempts = 0;
  static const _kMaxReconnectAttempts = 3;

  // ── Streams ───────────────────────────────────────────────────────────────
  final _stateCtrl = StreamController<GameState>.broadcast();
  final _logCtrl = StreamController<String>.broadcast();
  final _playersCtrl = StreamController<List<LanPlayer>>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();

  @override
  Stream<GameState> get stateStream => _stateCtrl.stream;
  @override
  Stream<String> get logStream => _logCtrl.stream;
  @override
  Stream<String> get errorStream => _errorCtrl.stream;
  @override
  Stream<List<LanPlayer>> get playerListStream => _playersCtrl.stream;

  // ── Relay-based connection ────────────────────────────────────────────────

  /// Creates a WebRTC offer, posts it to the shared room offer topic, and
  /// polls for the host's answer — all in one call.  Returns `true` on
  /// success (channel will open asynchronously; watch [stateStream]).
  Future<bool> connectWithCode({
    required String roomCode,
    required String playerId,
    required String displayName,
  }) async {
    _playerId = playerId;
    _displayName = displayName;
    _roomCode = roomCode;

    _log('CHECKING_RELAY_CONNECTIVITY...');
    if (!await WiredRelay.checkConnectivity()) {
      _errorCtrl.add('SIGNALING_SERVER_UNAVAILABLE');
      return false;
    }

    final sessionId = const Uuid().v4();
    final conn = WiredPeerConnection(sessionId);
    _conn = conn;

    _log('GENERATING_OFFER...');
    String offerSdp;
    try {
      offerSdp = await conn.createOffer();
    } catch (e) {
      _errorCtrl.add('OFFER_ERROR: $e');
      return false;
    }

    _log('POSTING_OFFER_TO_RELAY...');
    try {
      await WiredRelay.postGuestOffer(roomCode, sessionId, offerSdp);
    } catch (e) {
      _errorCtrl.add('RELAY_POST_ERROR: $e');
      return false;
    }

    _log('OFFER_POSTED \u2014 AWAITING_HOST_ANSWER...');
    _pollForAnswer(conn, roomCode, sessionId);
    return true;
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  /// Polls for the host's per-session answer every 3 s for up to ~4 min.
  Future<void> _pollForAnswer(
      WiredPeerConnection conn, String roomCode, String sessionId) async {
    for (int attempt = 0; attempt < 80; attempt++) {
      if (_conn != conn) return; // superseded by a new connection attempt

      final payload = await WiredRelay.pollHostAnswer(roomCode, sessionId);

      if (_conn != conn) return;

      if (payload != null && payload.sessionId == sessionId) {
        _log('HOST_ANSWER_RECEIVED \u2014 COMPLETING_HANDSHAKE...');
        try {
          await conn.acceptAnswer(payload.sdp);
        } catch (e) {
          _errorCtrl.add('HANDSHAKE_ERROR: $e');
          return;
        }
        _waitForChannel(conn);
        return;
      }

      await Future.delayed(const Duration(seconds: 3));
    }
    _errorCtrl.add('RELAY_POLL_TIMEOUT \u2014 host did not respond');
  }

  void _waitForChannel(WiredPeerConnection conn) {
    conn.onOpen.first.then((_) => _onChannelOpen(conn));
    conn.onClose.first.then((_) => _onChannelClosed());
  }

  void _onChannelOpen(WiredPeerConnection conn) {
    _log('CHANNEL_OPEN — JOINING_ROOM...');
    conn.messageStream.listen(_handleJson);

    // Announce ourselves to the host.
    conn.send(GameMessage.joinRoom(
      playerId: _playerId,
      roomId: _roomCode,
      displayName: _displayName,
    ).toJsonString());
  }

  void _onChannelClosed() {
    if (!_disposed) {
      _log('CONNECTION_LOST — RECONNECTING...');
      _scheduleWiredReconnect();
    } else {
      _log('CONNECTION_LOST');
      _errorCtrl.add('CONNECTION_LOST');
    }
  }

  void _scheduleWiredReconnect() {
    if (_disposed || _reconnectAttempts >= _kMaxReconnectAttempts) {
      _errorCtrl.add('CONNECTION_LOST');
      return;
    }
    _reconnectAttempts++;
    _log('WIRED_RECONNECT_ATTEMPT: $_reconnectAttempts/$_kMaxReconnectAttempts');
    Future.delayed(Duration(seconds: _reconnectAttempts * 5), () async {
      if (_disposed) return;
      final success = await connectWithCode(
        roomCode: _roomCode,
        playerId: _playerId,
        displayName: _displayName,
      );
      if (success) _reconnectAttempts = 0;
    });
  }

  void _handleJson(String json) {
    GameMessage msg;
    try {
      msg = GameMessage.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return;
    }

    switch (msg.type) {
      case MessageType.gameStateUpdate:
        final stateJson = msg.payload['state'] as Map<String, dynamic>?;
        final log = msg.payload['log'] as String?;
        if (stateJson != null) {
          final gs = GameState.fromJson(stateJson);
          _stateCtrl.add(gs);
          if (log != null && log.isNotEmpty) _log(log);
        }
      case MessageType.playerJoined:
        final p = msg.payload['player'] as Map<String, dynamic>?;
        if (p != null) {
          _log('PLAYER_JOINED: ${p['displayName'] ?? p['id']}');
        }
      case MessageType.playerLeft:
        final pid = msg.payload['playerId'] as String?;
        if (pid != null) _log('PLAYER_LEFT: $pid');
      case MessageType.gameOver:
        _log('GAME_OVER');
      case MessageType.error:
        final reason = msg.payload['reason'] as String? ?? 'UNKNOWN';
        _errorCtrl.add('SERVER_ERROR: $reason');
      default:
        break;
    }
  }

  // ── Send action ───────────────────────────────────────────────────────────

  @override
  void sendAction(GameMessage msg) {
    _conn?.send(msg.toJsonString());
  }

  void _log(String msg) => _logCtrl.add(msg);

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _conn?.dispose();
    _conn = null;

    await _stateCtrl.close();
    await _logCtrl.close();
    await _playersCtrl.close();
    await _errorCtrl.close();
  }
}
