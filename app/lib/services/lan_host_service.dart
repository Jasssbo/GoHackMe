import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:go_engine/go_engine.dart';

import 'i_game_transport.dart';
import 'lan_discovery_service.dart';
import 'connected_player.dart';

// ── _ClientConnection (internal) ───────────────────────────────────────────

class _ClientConn {
  final Socket socket;
  String? playerId;
  final StringBuffer _buf = StringBuffer();
  DateTime lastSeen = DateTime.now(); // updated on every pong received

  _ClientConn(this.socket);

  /// Appends incoming bytes and drains complete newline-terminated messages.
  Iterable<String> feed(List<int> data) {
    _buf.write(utf8.decode(data, allowMalformed: true));
    final raw = _buf.toString();
    final lines = raw.split('\n');
    _buf.clear();
    // The last element is an incomplete fragment (possibly empty).
    if (lines.isNotEmpty) _buf.write(lines.last);
    return lines.take(lines.length - 1).where((l) => l.trim().isNotEmpty);
  }
}

// ── LanHostService ─────────────────────────────────────────────────────────

/// Runs a TCP game server on a random LAN port and broadcasts UDP beacons
/// for automatic discovery.
///
/// The host device is player 0.  Remote devices connect via TCP, send a
/// [MessageType.joinRoom] message, and from then on exchange
/// [GameMessage] JSON lines.
///
/// Implements [IGameTransport] so [LanGameNotifier] can treat host and client
/// uniformly (DIP).  [sendAction] replaces the old [applyHostAction] and
/// bypasses the socket layer, applying actions directly to the engine.
class LanHostService implements IGameTransport {
  // ── TCP server ────────────────────────────────────────────────────────────
  ServerSocket? _server;
  final _beacon = LanBeaconBroadcaster();
  final _clients = <String, _ClientConn>{}; // playerId → conn

  // ── Game state ────────────────────────────────────────────────────────────
  GameState? _state;
  late String _hostPlayerId;
  late String _hostDisplayName;
  late String _roomCode;
  late int _boardSize;
  late int _maxPlayers;
  final List<ConnectedPlayer> _pending = []; // players waiting for game start

  /// Player IDs that disconnected after the game started.
  /// They may reconnect; their subnets are zeroed-out on disconnect.
  final Set<String> _disconnectedPlayers = {};

  /// Timers that expire the reconnect window (30 s) for each disconnected
  /// player.  When the timer fires the player is permanently marked offline.
  final _reconnectTimers = <String, Timer>{};

  // ── Streams ───────────────────────────────────────────────────────────────
  final _stateCtrl = StreamController<GameState>.broadcast();
  final _logCtrl = StreamController<String>.broadcast();
  final _playersCtrl = StreamController<List<ConnectedPlayer>>.broadcast();

  // Host never emits transport errors to the notifier; exposed via interface
  // with a no-op controller so subscribers receive an orderly close on dispose.
  final _errorCtrl = StreamController<String>.broadcast();

  // ── Keepalive ─────────────────────────────────────────────────────────────
  Timer? _pingTimer;
  static const _kPingInterval = Duration(seconds: 5);
  static const _kPingTimeout = Duration(seconds: 15);
  // ── Turn timer ───────────────────────────────────────────────
  Timer? _turnTimer;
  static const _kTurnTimeout = Duration(seconds: 15);
  @override
  Stream<GameState> get stateStream => _stateCtrl.stream;
  @override
  Stream<String> get logStream => _logCtrl.stream;
  @override
  Stream<String> get errorStream => _errorCtrl.stream;
  @override
  Stream<List<ConnectedPlayer>> get playerListStream => _playersCtrl.stream;

  List<ConnectedPlayer> get players => List.unmodifiable(_pending);
  GameState? get currentState => _state;
  String get roomCode => _roomCode;
  bool get gameStarted => _state != null;

  // ── Start ─────────────────────────────────────────────────────────────────

  /// Binds the server socket, begins advertising, and returns the TCP port.
  Future<int> startServer({
    required String roomCode,
    required String hostPlayerId,
    required String hostDisplayName,
    required int boardSize,
    required int maxPlayers,
  }) async {
    _roomCode = roomCode;
    _hostPlayerId = hostPlayerId;
    _hostDisplayName = hostDisplayName;
    _boardSize = boardSize;
    _maxPlayers = maxPlayers;

    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final port = _server!.port;

    _pending.add(ConnectedPlayer(id: hostPlayerId, displayName: hostDisplayName));
    _playersCtrl.add(players);

    final room = LanRoom(
      roomCode: roomCode,
      hostAddress: InternetAddress.anyIPv4,
      tcpPort: port,
      hostName: hostDisplayName,
      boardSize: boardSize,
      maxPlayers: maxPlayers,
      currentPlayers: 1,
      lastSeen: DateTime.now(),
    );
    await _beacon.start(room);

    _server!.listen(_onClientSocket);
    _pingTimer = Timer.periodic(_kPingInterval, (_) => _pingAll());
    _log('HOST_READY port=$port ROOM:$roomCode');
    return port;
  }

  // ── Incoming client connection ────────────────────────────────────────────

  void _onClientSocket(Socket socket) {
    _log('CLIENT_CONNECTED: ${socket.remoteAddress.address}');
    final conn = _ClientConn(socket);

    socket.listen(
      (data) {
        for (final line in conn.feed(data)) {
          _handleLine(conn, line);
        }
      },
      onDone: () => _onClientGone(conn),
      onError: (_) => _onClientGone(conn),
      cancelOnError: false,
    );
  }

  void _handleLine(_ClientConn conn, String line) {
    GameMessage msg;
    try {
      msg = GameMessage.fromJsonString(line);
    } catch (_) {
      return;
    }

    // Ping/pong are handled before the player-ID check because they carry no ID.
    if (msg.type == MessageType.ping) {
      _sendTo(conn, GameMessage.pong());
      return;
    }
    if (msg.type == MessageType.pong) {
      conn.lastSeen = DateTime.now();
      return;
    }

    final pid = msg.playerId;
    if (pid == null) return;

    // Identity enforcement: after join, ignore any message whose playerId
    // does not match the player ID bound to this socket connection.
    // This prevents a connected client from impersonating another player.
    if (msg.type != MessageType.joinRoom && conn.playerId != pid) return;

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

  void _handleJoin(_ClientConn conn, String pid, GameMessage msg) {
    // ── Reconnection: player was in the game but disconnected ──────────────
    if (_state != null && _disconnectedPlayers.contains(pid)) {
      _disconnectedPlayers.remove(pid);
      _reconnectTimers[pid]?.cancel();
      _reconnectTimers.remove(pid);
      conn.playerId = pid;
      _clients[pid] = conn;
      final displayName =
          _state!.players.firstWhere((p) => p.id == pid).displayName;
      _log('PLAYER_RECONNECTED: $displayName');
      // Send current state so the rejoinee is immediately in sync.
      _sendTo(
        conn,
        GameMessage(
          type: MessageType.gameStateUpdate,
          payload: {'state': _state!.toJson(), 'log': 'RECONNECTED'},
        ),
      );
      // Notify everyone.
      _broadcastAll(
        GameMessage(
          type: MessageType.playerJoined,
          payload: {'player': {'id': pid, 'displayName': displayName}},
        ),
      );
      return;
    }

    // ── Reject if game already started and this is NOT a reconnect ─────────
    if (_state != null) {
      if (_pending.length >= _maxPlayers) {
        _sendTo(
          conn,
          const GameMessage(
            type: MessageType.error,
            payload: {'reason': 'ROOM_FULL'},
          ),
        );
        return;
      }

      // ── New player joining a game already in progress ────────────────────
      final rawNameMid = msg.payload['displayName'] as String? ?? pid;
      final displayName = rawNameMid.length > 32 ? rawNameMid.substring(0, 32) : rawNameMid;
      conn.playerId = pid;
      _clients[pid] = conn;
      _pending.add(ConnectedPlayer(id: pid, displayName: displayName));
      _playersCtrl.add(players);

      // Splice the new player into the live GameState.
      final newPlayer = Player(id: pid, displayName: displayName);
      final newPlayers = [..._state!.players, newPlayer];
      _state = _state!.copyWith(
        players: newPlayers,
        subnets: {..._state!.subnets, pid: 0},
        captureCount: {..._state!.captureCount, pid: 0},
        patchShields: {..._state!.patchShields, pid: 0},
        backdoorBy: {..._state!.backdoorBy, pid: null},
      );

      _log('PLAYER_JOINED_MIDGAME: $displayName');

      // Send the joiner the current state immediately.
      _sendTo(
        conn,
        GameMessage(
          type: MessageType.gameStateUpdate,
          payload: {'state': _state!.toJson(), 'log': 'WIRED_IN'},
        ),
      );
      // Notify everyone else.
      _broadcastAll(
        GameMessage(
          type: MessageType.playerJoined,
          payload: {'player': {'id': pid, 'displayName': displayName}},
        ),
      );
      // Broadcast updated state to all (so existing players see the new
      // player in the roster and the new subnet / player-list counts).
      _broadcastStateUpdate('>> NEW_NODE :: $displayName WIRED_IN');

      _beacon.updateRoom(LanRoom(
        roomCode: _roomCode,
        hostAddress: InternetAddress.anyIPv4,
        tcpPort: _server!.port,
        hostName: _hostDisplayName,
        boardSize: _boardSize,
        maxPlayers: _maxPlayers,
        currentPlayers: _pending.length,
        lastSeen: DateTime.now(),
        gameInProgress: true,
      ));
      return;
    }
    if (_pending.length >= _maxPlayers) {
      _sendTo(
        conn,
        const GameMessage(
          type: MessageType.error,
          payload: {'reason': 'ROOM_FULL'},
        ),
      );
      return;
    }

    final rawName = msg.payload['displayName'] as String? ?? pid;
    final displayName = rawName.length > 32 ? rawName.substring(0, 32) : rawName;
    conn.playerId = pid;
    _clients[pid] = conn;
    _pending.add(ConnectedPlayer(id: pid, displayName: displayName));
    _playersCtrl.add(players);

    // Send the new client a playerJoined message for every player that was
    // already in the room (including the host) so their waiting-room list
    // stays in sync.
    for (final existing in _pending) {
      if (existing.id == pid) continue; // skip themselves
      _sendTo(
        conn,
        GameMessage(
          type: MessageType.playerJoined,
          payload: {'player': {'id': existing.id, 'displayName': existing.displayName}},
        ),
      );
    }
    _beacon.updateRoom(LanRoom(
      roomCode: _roomCode,
      hostAddress: InternetAddress.anyIPv4,
      tcpPort: _server!.port,
      hostName: _hostDisplayName,
      boardSize: _boardSize,
      maxPlayers: _maxPlayers,
      currentPlayers: _pending.length,
      lastSeen: DateTime.now(),
    ));

    _broadcastAll(
      GameMessage(
        type: MessageType.playerJoined,
        payload: {'player': {'id': pid, 'displayName': displayName}},
      ),
    );
    _log('PLAYER_JOINED: $displayName');

    if (_pending.length >= _maxPlayers) _startCountdown();
  }

  void _onClientGone(_ClientConn conn) {
    final pid = conn.playerId;
    if (pid == null) return;
    _clients.remove(pid);

    if (_state == null) {
      // Pre-game: simply remove from the lobby.
      _pending.removeWhere((p) => p.id == pid);
      _playersCtrl.add(players);
      _log('PLAYER_LEFT_LOBBY: $pid');
      _broadcastAll(
          GameMessage(type: MessageType.playerLeft, payload: {'playerId': pid}));
      return;
    }

    // ── Mid-game disconnect ────────────────────────────────────────────────
    _disconnectedPlayers.add(pid);

    // 30-second window: if they don't reconnect, close their slot.
    _reconnectTimers[pid]?.cancel();
    _reconnectTimers[pid] = Timer(const Duration(seconds: 30), () {
      _disconnectedPlayers.remove(pid);
      _reconnectTimers.remove(pid);
      _log('RECONNECT_TIMEOUT: $pid — slot permanently closed');
    });

    final name = _state!.players
        .firstWhere((p) => p.id == pid,
            orElse: () => Player(id: pid, displayName: pid))
        .displayName;
    _log('PLAYER_DISCONNECTED: $name');

    // Redistribute their subnets evenly among still-connected players.
    _redistributeSubnets(pid);

    _broadcastAll(
        GameMessage(type: MessageType.playerLeft, payload: {'playerId': pid}));

    // Broadcast updated state (new subnet values) and auto-skip if needed.
    _broadcastStateUpdate('>> SIGNAL_LOST :: $name DISCONNECTED');
    _autoSkipDisconnected();
  }

  /// Moves [playerId]'s subnets evenly to all currently connected players.
  void _redistributeSubnets(String playerId) {
    final amount = _state!.subnetsOf(playerId);
    if (amount <= 0) return;

    final active = _state!.players
        .where((p) => p.id != playerId && !_disconnectedPlayers.contains(p.id))
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

  /// Auto-passes for every disconnected player that currently holds the
  /// active turn.  Loops until the current player is connected or the game
  /// ends.  Has a guard to avoid infinite loops if everyone disconnects.
  void _autoSkipDisconnected() {
    if (_state == null || _disconnectedPlayers.isEmpty) return;

    int guard = 0;
    final maxGuard = _state!.players.length;

    while (guard < maxGuard &&
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
          _broadcastAll(
              GameMessage(type: MessageType.gameOver, payload: {}));
          _beacon.stop();
          _log('GAME_OVER');
          return;
        }
      } else {
        break;
      }
    }
  }

  // ── Host action (no socket round-trip) ───────────────────────────────────

  /// Implements [IGameTransport.sendAction].
  ///
  /// Applies the action directly to the engine without a socket round-trip,
  /// ensuring the host's own moves are authoritative without latency.
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
      default:
        break;
    }
  }

  // ── Start game ────────────────────────────────────────────────────────────
  /// Called automatically when the lobby fills; counts down 3 s then starts.
  void _startCountdown() {
    var remaining = 3;
    _log('ALL_NODES_WIRED — LAUNCHING_IN: $remaining');
    Timer.periodic(const Duration(seconds: 1), (t) {
      remaining--;
      if (remaining > 0) {
        _log('LAUNCHING_IN: $remaining');
      } else {
        t.cancel();
        startGame();
      }
    });
  }
  void startGame() {
    if (_state != null) return;
    // Keep the beacon alive so disconnected players can still discover and
    // reconnect.  It will be stopped when the game ends.
    _beacon.updateRoom(LanRoom(
      roomCode: _roomCode,
      hostAddress: InternetAddress.anyIPv4,
      tcpPort: _server!.port,
      hostName: _hostDisplayName,
      boardSize: _boardSize,
      maxPlayers: _maxPlayers,
      currentPlayers: _pending.length,
      lastSeen: DateTime.now(),
      gameInProgress: true,
    ));

    final ps = _pending
        .map((p) => Player(id: p.id, displayName: p.displayName))
        .toList();
    _state = GameState.newGame(players: ps, boardSize: _boardSize);

    // Notify the host's own UI — clients get it via _broadcastStateUpdate.
    _stateCtrl.add(_state!);
    _broadcastStateUpdate('GAME_START');
    _log('GAME_STARTED players=${_pending.length}');
    _resetTurnTimer();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _isCurrentPlayer(String pid) =>
      _state != null && _state!.currentPlayerId == pid;
  void _resetTurnTimer() {
    _turnTimer?.cancel();
    if (_state == null || _state!.phase == GamePhase.scoring) return;
    final playerId = _state!.currentPlayerId;
    _turnTimer = Timer(_kTurnTimeout, () {
      if (_state == null) return;
      if (_state!.currentPlayerId != playerId) return;
      _log('TURN_TIMEOUT: auto-acting for player=$playerId phase=${_state!.phase.name}');
      final ActionResult result;
      if (_state!.phase == GamePhase.attack) {
        result = GameEngine.endAttackPhase(_state!, playerId);
      } else {
        result = GameEngine.pass(_state!, playerId);
      }
      if (result is ActionSuccess) {
        _state = result.newState;
        _stateCtrl.add(_state!);
        _broadcastStateUpdate('TURN_TIMEOUT');
        if (GameEngine.isGameOver(_state!)) {
          _broadcastAll(GameMessage(type: MessageType.gameOver, payload: {}));
          _beacon.stop();
          _turnTimer?.cancel();
          _log('GAME_OVER');
          return;
        }
        _autoSkipDisconnected();
        if (_checkLastEntityStanding()) return;
        _resetTurnTimer();
      }
    });
  }

  /// Returns true (and ends the game) if only one entity is still connected.
  /// Only triggers when the game started with more than one player.
  bool _checkLastEntityStanding() {
    if (_state == null) return false;
    if (_state!.players.length <= 1) return false;
    final active = _state!.players
        .where((p) => !_disconnectedPlayers.contains(p.id))
        .toList();
    if (active.length != 1) return false;
    final winner = active.first;
    _log('LAST_ENTITY_STANDING: ${winner.displayName} wins by forfeit');
    _broadcastStateUpdate('>> LAST_ENTITY_STANDING :: ${winner.displayName} WINS BY FORFEIT');
    _broadcastAll(GameMessage(type: MessageType.gameOver, payload: {}));
    _beacon.stop();
    _turnTimer?.cancel();
    return true;
  }

  void _applyResult(ActionResult result) {
    switch (result) {
      case ActionSuccess(:final newState, :final logMessage):
        _state = newState;
        _stateCtrl.add(_state!);
        _broadcastStateUpdate(logMessage ?? '');

        if (GameEngine.isGameOver(_state!)) {
          _broadcastAll(GameMessage(type: MessageType.gameOver, payload: {}));
          _beacon.stop(); // Room is finished — stop advertising.
          _turnTimer?.cancel();
          _log('GAME_OVER');
          return;
        }
        // Auto-skip any disconnected players who now hold the turn.
        _autoSkipDisconnected();
        _resetTurnTimer();

      case ActionFailure(:final reason):
        _log('ACTION_ERROR: $reason');
    }
  }

  void _broadcastStateUpdate(String log) {
    final msg = GameMessage(
      type: MessageType.gameStateUpdate,
      payload: {'state': _state!.toJson(), 'log': log},
    );
    _broadcastAll(msg);
    if (log.isNotEmpty) _logCtrl.add(log);
  }

  void _broadcastAll(GameMessage msg) {
    final line = '${msg.toJsonString()}\n';
    for (final conn in _clients.values) {
      try {
        conn.socket.write(line);
        conn.socket.flush();
      } catch (_) {}
    }
  }

  void _sendTo(_ClientConn conn, GameMessage msg) {
    try {
      conn.socket.write('${msg.toJsonString()}\n');
      conn.socket.flush();
    } catch (_) {}
  }

  void _log(String msg) => _logCtrl.add(msg);

  /// Sends a ping to all connected clients and drops any that have not
  /// responded within [_kPingTimeout].
  void _pingAll() {
    final now = DateTime.now();
    final stale = _clients.values
        .where((c) => now.difference(c.lastSeen) > _kPingTimeout)
        .toList();
    for (final c in stale) {
      _log('PING_TIMEOUT: ${c.playerId ?? "unknown"}');
      _onClientGone(c);
      c.socket.close().ignore();
    }
    _broadcastAll(GameMessage.ping());
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    for (final t in _reconnectTimers.values) { t.cancel(); }
    _reconnectTimers.clear();
    _beacon.stop();
    for (final c in _clients.values) {
      try {
        await c.socket.close();
      } catch (_) {}
    }
    _clients.clear();
    await _server?.close();
    _server = null;
    if (!_stateCtrl.isClosed) await _stateCtrl.close();
    if (!_logCtrl.isClosed) await _logCtrl.close();
    if (!_playersCtrl.isClosed) await _playersCtrl.close();
    if (!_errorCtrl.isClosed) await _errorCtrl.close();
  }
}
