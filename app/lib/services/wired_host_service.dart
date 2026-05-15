import 'dart:async';
import 'dart:convert';

import 'package:go_engine/go_engine.dart';

import 'i_game_transport.dart';
import 'lan_player.dart';
import 'webrtc_wired_service.dart';
import 'wired_relay_service.dart';

// ── WiredHostService ──────────────────────────────────────────────────────

/// WebRTC-based game server for "The Wired" mode.
///
/// The host device runs the authoritative [GameEngine].  Clients connect
/// via WebRTC data channels.  SDP negotiation is handled automatically
/// through a free ntfy.sh relay — the host only needs to share a short
/// 8-character relay code with each guest.
///
/// Multiplayer flow:
///   1. Host calls [open] → initialises, adds self to pending players.
///   2. For each incoming player: host calls [createInviteCode] → shares
///      the returned 8-char relay code with the guest out-of-band.
///   3. Guest enters the relay code → their SDP answer is posted to relay.
///   4. Host's background polling detects the answer → channel opens →
///      guest appears in [playerListStream].  No manual response needed.
///   5. Host calls [startGame()] when ready (≥ 2 players required).
///
/// Security: see [WiredPeerConnection] for message-level protections.
/// All game-state mutations go through [GameEngine] validation (host auth).
class WiredHostService implements IGameTransport {
  // ── Connections ───────────────────────────────────────────────────────────

  /// Active connections keyed by sessionId (established + pending).
  final _conns = <String, WiredPeerConnection>{};

  /// SessionIds that have a fully-open data channel.
  final _activeSessionIds = <String>{};

  /// Session IDs whose offers we have already processed (prevents re-handling
  /// the same offer on subsequent poll cycles).
  final _seenSessionIds = <String>{};

  /// Set to false to stop the background offer-polling loop.
  bool _isListening = false;

  bool _isDisposed = false;

  // ── Game state ────────────────────────────────────────────────────────────
  GameState? _state;
  late String _hostPlayerId;
  late String _roomCode;
  late int _boardSize;
  late int _maxPlayers;
  final List<LanPlayer> _pending = []; // lobby list
  final Set<String> _disconnectedPlayers = {};

  /// Timers that expire the reconnect window (30 s) for each disconnected
  /// guest.  When the timer fires the slot is permanently closed.
  final _reconnectTimers = <String, Timer>{};

  // ── Streams ───────────────────────────────────────────────────────────────
  final _stateCtrl = StreamController<GameState>.broadcast();
  final _logCtrl = StreamController<String>.broadcast();
  final _playersCtrl = StreamController<List<LanPlayer>>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();

  // Extra: stream specifically for the wired-screen invite-flow progress.
  final _statusCtrl = StreamController<String>.broadcast();

  @override
  Stream<GameState> get stateStream => _stateCtrl.stream;
  @override
  Stream<String> get logStream => _logCtrl.stream;
  @override
  Stream<String> get errorStream => _errorCtrl.stream;
  @override
  Stream<List<LanPlayer>> get playerListStream => _playersCtrl.stream;

  /// Human-readable status events (invite code created, player connected, …)
  /// consumed by the waiting-room UI.
  Stream<String> get statusStream => _statusCtrl.stream;

  List<LanPlayer> get players => List.unmodifiable(_pending);
  GameState? get currentState => _state;
  String get roomCode => _roomCode;
  bool get gameStarted => _state != null;

  // ── Setup ─────────────────────────────────────────────────────────────────

  void open({
    required String roomCode,
    required String hostPlayerId,
    required String hostDisplayName,
    required int boardSize,
    required int maxPlayers,
  }) {
    _roomCode = roomCode;
    _hostPlayerId = hostPlayerId;
    _boardSize = boardSize;
    _maxPlayers = maxPlayers;

    _pending.add(LanPlayer(id: hostPlayerId, displayName: hostDisplayName));
    _playersCtrl.add(players);
    _log('WIRED_HOST_READY ROOM:$roomCode');

    // Immediately start listening for guest offers on the shared room topic.
    _startListeningForGuests();
  }

  // ── Guest-offer listener ──────────────────────────────────────────────────

  /// Polls the shared offer topic every 3 s for up to ~4 min.
  ///
  /// Each new guest posts its SDP offer to `ghm-{roomCode}-o`; this loop
  /// picks them up, generates an answer, and posts it to
  /// `ghm-{roomCode}-a-{sessionId}` so each guest gets exactly its own answer.
  void _startListeningForGuests({int maxAttempts = 80}) async {
    _isListening = true;
    _log('CHECKING_RELAY_CONNECTIVITY...');
    if (!await WiredRelay.checkConnectivity()) {
      _errorCtrl.add('SIGNALING_SERVER_UNAVAILABLE');
      _isListening = false;
      return;
    }
    for (int attempt = 0; attempt < maxAttempts && _isListening && !_isDisposed; attempt++) {
      try {
        final offers = await WiredRelay.fetchAllGuestOffers(_roomCode);
        for (final offer in offers) {
          if (_isDisposed || !_isListening) return;
          if (_seenSessionIds.contains(offer.sessionId)) continue;
          _seenSessionIds.add(offer.sessionId);
          // Handle in the background — don't block the poll loop.
          _acceptGuestOffer(offer);
        }
      } catch (_) {}
      if (!_isListening || _isDisposed) return;
      await Future.delayed(const Duration(seconds: 3));
    }
    _isListening = false;
  }

  /// Completes the WebRTC handshake for one guest offer.
  Future<void> _acceptGuestOffer(WiredRelayPayload offer) async {
    final conn = WiredPeerConnection(offer.sessionId);
    _conns[offer.sessionId] = conn;

    _log('GUEST_OFFER_RECEIVED sid=${offer.sessionId.substring(0, 8)}');

    String answerSdp;
    try {
      answerSdp = await conn.createAnswer(offer.sdp);
    } catch (e) {
      _log('ANSWER_ERROR: $e');
      _conns.remove(offer.sessionId);
      return;
    }

    try {
      await WiredRelay.postHostAnswer(_roomCode, offer.sessionId, answerSdp);
    } catch (e) {
      _log('RELAY_POST_ERROR: $e');
      _conns.remove(offer.sessionId);
      return;
    }

    _log('ANSWER_POSTED — waiting for channel sid=${offer.sessionId.substring(0, 8)}');

    try {
      await conn.onOpen.first.timeout(const Duration(seconds: 20));
    } catch (_) {
      _log('CHANNEL_OPEN_TIMEOUT sid=${offer.sessionId.substring(0, 8)}');
      _conns.remove(offer.sessionId);
      return;
    }

    if (!conn.isOpen) {
      _conns.remove(offer.sessionId);
      return;
    }

    _activeSessionIds.add(conn.sessionId);
    _listenToConnection(conn);
    _statusCtrl.add('PLAYER_CHANNEL_OPEN:${conn.sessionId}');
    _log('CHANNEL_OPEN sid=${conn.sessionId}');
  }

  // ── Start game ────────────────────────────────────────────────────────────

  void startGame() {
    if (_state != null) return;
    if (_pending.length < 2) return;

    final ps =
        _pending.map((p) => Player(id: p.id, displayName: p.displayName)).toList();
    _state = GameState.newGame(players: ps, boardSize: _boardSize);

    _stateCtrl.add(_state!);
    _broadcastStateUpdate('GAME_START');
    _log('GAME_STARTED players=${_pending.length}');
  }

  // ── Connection management ─────────────────────────────────────────────────

  void _listenToConnection(WiredPeerConnection conn) {
    conn.messageStream.listen((json) => _handleJson(conn, json));
    conn.onClose.first.then((_) => _onConnectionClosed(conn));
  }

  void _onConnectionClosed(WiredPeerConnection conn) {
    _activeSessionIds.remove(conn.sessionId);
    _conns.remove(conn.sessionId);

    final pid = conn.boundPlayerId;
    if (pid == null) return;

    if (_state == null) {
      _pending.removeWhere((p) => p.id == pid);
      _playersCtrl.add(players);
      _log('PLAYER_LEFT_LOBBY: $pid');
      _broadcastAll(
          GameMessage(type: MessageType.playerLeft, payload: {'playerId': pid}));
      return;
    }

    _disconnectedPlayers.add(pid);

    // 30-second window: if the guest doesn't reconnect, close their slot.
    _reconnectTimers[pid]?.cancel();
    _reconnectTimers[pid] = Timer(const Duration(seconds: 30), () {
      _disconnectedPlayers.remove(pid);
      _reconnectTimers.remove(pid);
      _log('RECONNECT_TIMEOUT: $pid — slot permanently closed');
    });

    // Restart the offer-listener (may have exhausted its budget) so the
    // guest's new offer will be picked up within the 30-second window.
    if (!_isListening && !_isDisposed) {
      _startListeningForGuests(maxAttempts: 10); // 10 × 3 s = 30 s
    }
    final name = _state!.players
        .firstWhere((p) => p.id == pid,
            orElse: () => Player(id: pid, displayName: pid))
        .displayName;
    _log('PLAYER_DISCONNECTED: $name');
    _redistributeSubnets(pid);
    _broadcastAll(
        GameMessage(type: MessageType.playerLeft, payload: {'playerId': pid}));
    _broadcastStateUpdate('>> SIGNAL_LOST :: $name DISCONNECTED');
    _autoSkipDisconnected();
  }

  // ── Message routing ───────────────────────────────────────────────────────

  void _handleJson(WiredPeerConnection conn, String json) {
    GameMessage msg;
    try {
      msg = GameMessage.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return;
    }

    final pid = msg.playerId;
    if (pid == null) return;

    // Identity binding — once a player ID is established for a connection,
    // it cannot change.
    if (!conn.tryBindPlayerId(pid)) return;

    switch (msg.type) {
      case MessageType.joinRoom:
        _handleJoin(conn, pid, msg);
      case MessageType.placeStone:
        if (!_isCurrentPlayer(pid)) return;
        final x = msg.payload['x'] as int?;
        final y = msg.payload['y'] as int?;
        if (x != null && y != null) {
          _applyResult(GameEngine.placeStone(_state!, pid, Position(x, y)));
        }
      case MessageType.pass:
        if (!_isCurrentPlayer(pid)) return;
        _applyResult(GameEngine.pass(_state!, pid));
      case MessageType.performAttack:
        if (!_isCurrentPlayer(pid)) return;
        try {
          final a = AttackAction.fromJson(msg.payload);
          _applyResult(GameEngine.launchAttack(_state!, a));
        } catch (e) {
          _log('ATTACK_PARSE_ERROR: $e');
        }
      case MessageType.endAttackPhase:
        if (!_isCurrentPlayer(pid)) return;
        _applyResult(GameEngine.endAttackPhase(_state!, pid));
      default:
        break;
    }
  }

  void _handleJoin(WiredPeerConnection conn, String pid, GameMessage msg) {
    // Reconnect path
    if (_state != null && _disconnectedPlayers.contains(pid)) {
      _disconnectedPlayers.remove(pid);
      _reconnectTimers[pid]?.cancel();
      _reconnectTimers.remove(pid);
      final displayName =
          _state!.players.firstWhere((p) => p.id == pid).displayName;
      _log('PLAYER_RECONNECTED: $displayName');
      _sendTo(conn,
          GameMessage(
            type: MessageType.gameStateUpdate,
            payload: {'state': _state!.toJson(), 'log': 'RECONNECTED'},
          ));
      _broadcastAll(GameMessage(
        type: MessageType.playerJoined,
        payload: {'player': {'id': pid, 'displayName': displayName}},
      ));
      return;
    }

    if (_pending.length >= _maxPlayers) {
      _sendTo(conn,
          const GameMessage(
            type: MessageType.error,
            payload: {'reason': 'ROOM_FULL'},
          ));
      return;
    }

    final rawName = msg.payload['displayName'] as String? ?? pid;
    final displayName = rawName.length > 32 ? rawName.substring(0, 32) : rawName;

    // Mid-game late join
    if (_state != null) {
      _pending.add(LanPlayer(id: pid, displayName: displayName));
      _playersCtrl.add(players);
      _state = _state!.copyWith(
        players: [..._state!.players, Player(id: pid, displayName: displayName)],
        subnets: {..._state!.subnets, pid: 0},
        captureCount: {..._state!.captureCount, pid: 0},
        patchShields: {..._state!.patchShields, pid: 0},
        backdoorBy: {..._state!.backdoorBy, pid: null},
      );
      _log('PLAYER_JOINED_MIDGAME: $displayName');
      _sendTo(conn,
          GameMessage(
            type: MessageType.gameStateUpdate,
            payload: {'state': _state!.toJson(), 'log': 'WIRED_IN'},
          ));
      _broadcastAll(GameMessage(
        type: MessageType.playerJoined,
        payload: {'player': {'id': pid, 'displayName': displayName}},
      ));
      _broadcastStateUpdate('>> NEW_NODE :: $displayName WIRED_IN');
      return;
    }

    // Normal pre-game join
    _pending.add(LanPlayer(id: pid, displayName: displayName));
    _playersCtrl.add(players);

    // Tell the newcomer about everyone already in the lobby.
    for (final existing in _pending) {
      if (existing.id == pid) continue;
      _sendTo(conn,
          GameMessage(
            type: MessageType.playerJoined,
            payload: {'player': {'id': existing.id, 'displayName': existing.displayName}},
          ));
    }

    _broadcastAll(GameMessage(
      type: MessageType.playerJoined,
      payload: {'player': {'id': pid, 'displayName': displayName}},
    ));
    _log('PLAYER_JOINED: $displayName');
    _statusCtrl.add('PLAYER_JOINED:$displayName');
  }

  // ── Host action (no round-trip) ───────────────────────────────────────────

  @override
  void sendAction(GameMessage msg) {
    if (_state == null) return;
    if (!_isCurrentPlayer(_hostPlayerId)) return;
    switch (msg.type) {
      case MessageType.placeStone:
        final x = msg.payload['x'] as int?;
        final y = msg.payload['y'] as int?;
        if (x != null && y != null) {
          _applyResult(
              GameEngine.placeStone(_state!, _hostPlayerId, Position(x, y)));
        }
      case MessageType.pass:
        _applyResult(GameEngine.pass(_state!, _hostPlayerId));
      case MessageType.performAttack:
        try {
          final a = AttackAction.fromJson(msg.payload);
          _applyResult(GameEngine.launchAttack(_state!, a));
        } catch (e) {
          _log('ATTACK_PARSE_ERROR: $e');
        }
      case MessageType.endAttackPhase:
        _applyResult(GameEngine.endAttackPhase(_state!, _hostPlayerId));
      default:
        break;
    }
  }

  // ── Game engine helpers ───────────────────────────────────────────────────

  bool _isCurrentPlayer(String pid) =>
      _state != null && _state!.currentPlayerId == pid;

  void _applyResult(ActionResult result) {
    switch (result) {
      case ActionSuccess(:final newState, :final logMessage):
        _state = newState;
        _stateCtrl.add(_state!);
        _broadcastStateUpdate(logMessage ?? '');
        if (GameEngine.isGameOver(_state!)) {
          _broadcastAll(GameMessage(type: MessageType.gameOver, payload: {}));
          _log('GAME_OVER');
          return;
        }
        _autoSkipDisconnected();
      case ActionFailure(:final reason):
        _log('ACTION_ERROR: $reason');
    }
  }

  void _redistributeSubnets(String playerId) {
    final amount = _state!.subnetsOf(playerId);
    if (amount <= 0) return;
    final active = _state!.players
        .where((p) =>
            p.id != playerId && !_disconnectedPlayers.contains(p.id))
        .toList();
    if (active.isEmpty) return;
    final newSubnets = Map<String, int>.from(_state!.subnets);
    final share = amount ~/ active.length;
    var leftover = amount - share * active.length;
    for (final p in active) {
      final bonus = leftover > 0 ? 1 : 0;
      leftover -= bonus;
      newSubnets[p.id] = (newSubnets[p.id] ?? 0) + share + bonus;
    }
    newSubnets[playerId] = 0;
    _state = _state!.copyWith(subnets: newSubnets);
  }

  void _autoSkipDisconnected() {
    if (_state == null || _disconnectedPlayers.isEmpty) return;
    int guard = 0;
    while (guard < _state!.players.length &&
        _state!.phase == GamePhase.attack &&
        _disconnectedPlayers.contains(_state!.currentPlayerId)) {
      guard++;
      final pid = _state!.currentPlayerId;
      final name = _state!.players
          .firstWhere((p) => p.id == pid,
              orElse: () => Player(id: pid, displayName: pid))
          .displayName;
      final result = GameEngine.pass(_state!, pid);
      if (result is ActionSuccess) {
        _state = result.newState;
        _stateCtrl.add(_state!);
        _broadcastStateUpdate('>> AUTO_SKIP :: $name OFFLINE');
        if (GameEngine.isGameOver(_state!)) {
          _broadcastAll(GameMessage(type: MessageType.gameOver, payload: {}));
          _log('GAME_OVER');
          return;
        }
      } else {
        break;
      }
    }
  }

  // ── Broadcast helpers ─────────────────────────────────────────────────────

  void _broadcastStateUpdate(String log) {
    final msg = GameMessage(
      type: MessageType.gameStateUpdate,
      payload: {'state': _state!.toJson(), 'log': log},
    );
    _broadcastAll(msg);
    if (log.isNotEmpty) _logCtrl.add(log);
  }

  void _broadcastAll(GameMessage msg) {
    final json = msg.toJsonString();
    for (final sid in _activeSessionIds) {
      _conns[sid]?.send(json);
    }
  }

  void _sendTo(WiredPeerConnection conn, GameMessage msg) {
    conn.send(msg.toJsonString());
  }

  void _log(String msg) {
    if (!_logCtrl.isClosed) _logCtrl.add(msg);
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    _isListening = false;
    for (final t in _reconnectTimers.values) { t.cancel(); }
    _reconnectTimers.clear();
    for (final conn in _conns.values) {
      await conn.dispose();
    }
    _conns.clear();
    _activeSessionIds.clear();

    await _stateCtrl.close();
    await _logCtrl.close();
    await _playersCtrl.close();
    await _errorCtrl.close();
    await _statusCtrl.close();
  }
}
