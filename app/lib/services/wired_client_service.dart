import 'dart:async';
import 'dart:convert';

import 'package:go_engine/go_engine.dart';

import 'i_game_transport.dart';
import 'lan_player.dart';
import 'webrtc_wired_service.dart';
import 'wired_relay_service.dart';

// ── WiredClientService ────────────────────────────────────────────────────

/// WebRTC client for "The Wired" mode.
///
/// Flow:
///   1. Caller receives the host's 8-char relay code.
///   2. [connectWithCode] fetches the SDP offer from the relay, generates an
///      answer, and posts it back — all automatically.
///   3. The host's background polling detects the answer and opens the channel.
///   4. [WiredClientService] sends a [MessageType.joinRoom] message.
///   5. The host broadcasts [GameState] updates; [stateStream] emits them.
class WiredClientService implements IGameTransport {
  WiredPeerConnection? _conn;

  late String _playerId;
  late String _displayName;
  late String _roomCode;

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

  /// Fetches the host's SDP offer from the relay, generates an answer, and
  /// posts it back — all in one call.  Returns `true` on success.
  ///
  /// After this returns, listen to [stateStream] for game state updates.
  Future<bool> connectWithCode({
    required String relayCode,
    required String playerId,
    required String displayName,
    required String roomCode,
  }) async {
    _playerId = playerId;
    _displayName = displayName;
    _roomCode = roomCode;

    _log('FETCHING_OFFER_FROM_RELAY...');
    final payload = await WiredRelay.fetchOffer(relayCode);
    if (payload == null) {
      _errorCtrl.add('OFFER_NOT_FOUND — check the code and try again');
      return false;
    }

    final conn = WiredPeerConnection(payload.sessionId);
    _conn = conn;

    _log('GENERATING_ANSWER...');
    String answerSdp;
    try {
      answerSdp = await conn.createAnswer(payload.sdp);
    } catch (e) {
      _errorCtrl.add('ANSWER_ERROR: $e');
      return false;
    }

    _log('POSTING_ANSWER_TO_RELAY...');
    try {
      await WiredRelay.postAnswer(relayCode, payload.sessionId, answerSdp);
    } catch (e) {
      _errorCtrl.add('RELAY_POST_ERROR: $e');
      return false;
    }

    _waitForChannel(conn);
    _log('ANSWER_SENT — AWAITING_CHANNEL...');
    return true;
  }

  // ── Internals ─────────────────────────────────────────────────────────────

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
    _log('CONNECTION_LOST');
    _errorCtrl.add('CONNECTION_LOST');
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
    await _conn?.dispose();
    _conn = null;

    await _stateCtrl.close();
    await _logCtrl.close();
    await _playersCtrl.close();
    await _errorCtrl.close();
  }
}
