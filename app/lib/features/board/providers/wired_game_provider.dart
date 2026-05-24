import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';
import 'package:uuid/uuid.dart';

import '../../../services/i_game_transport.dart';
import '../../../services/connected_player.dart';
import '../../../services/wired_server_service.dart';

// ── WiredRole ─────────────────────────────────────────────────────────────

enum WiredRole { host, client }

// ── WiredStatus ───────────────────────────────────────────────────────────

enum WiredStatus {
  /// Nothing initialised.
  idle,
  /// Connecting to the server.
  connecting,
  /// Server is in sleep mode (Render.com cold start); retrying automatically.
  waking,
  /// Connected — waiting for enough players / host to start.
  waiting,
  /// Game in progress.
  playing,
  /// Game finished.
  over,
  /// Error occurred.
  error,
}

// ── WiredGameState ────────────────────────────────────────────────────────

class WiredGameState {
  final WiredStatus status;
  final WiredRole? role;
  final GameState? gameState;
  final List<String> logLines;
  final String localPlayerId;
  final String roomCode;
  final List<ConnectedPlayer> connectedPlayers;
  final int maxPlayers;
  final String? errorMessage;

  const WiredGameState({
    this.status = WiredStatus.idle,
    this.role,
    this.gameState,
    this.logLines = const [],
    this.localPlayerId = '',
    this.roomCode = '',
    this.connectedPlayers = const [],
    this.maxPlayers = 2,
    this.errorMessage,
  });

  WiredGameState copyWith({
    WiredStatus? status,
    WiredRole? role,
    GameState? gameState,
    List<String>? logLines,
    String? localPlayerId,
    String? roomCode,
    List<ConnectedPlayer>? connectedPlayers,
    int? maxPlayers,
    String? errorMessage,
  }) =>
      WiredGameState(
        status: status ?? this.status,
        role: role ?? this.role,
        gameState: gameState ?? this.gameState,
        logLines: logLines ?? this.logLines,
        localPlayerId: localPlayerId ?? this.localPlayerId,
        roomCode: roomCode ?? this.roomCode,
        connectedPlayers: connectedPlayers ?? this.connectedPlayers,
        maxPlayers: maxPlayers ?? this.maxPlayers,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── WiredGameNotifier ─────────────────────────────────────────────────────

class WiredGameNotifier extends Notifier<WiredGameState> {
  // Raised from 60 to 200 to accommodate in-game chat messages.
  static const _maxLogLines = 200;

  IGameTransport? _transport;
  final List<StreamSubscription> _subs = [];

  @override
  WiredGameState build() {
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
      _transport?.dispose();
    });
    return const WiredGameState();
  }

  // ── Host ──────────────────────────────────────────────────────────────────

  /// Opens a new room on the server and waits for other players.
  Future<void> openAsHost({
    required String playerId,
    required String displayName,
    required int boardSize,
    required int maxPlayers,
  }) async {
    await _reset();
    final roomCode = const Uuid().v4().substring(0, 6).toUpperCase();
    final svc = WiredServerService();
    _transport = svc;

    state = WiredGameState(
      status: WiredStatus.waking,
      role: WiredRole.host,
      localPlayerId: playerId,
      roomCode: roomCode,
      maxPlayers: maxPlayers,
    );

    _subscribeToTransport();

    try {
      await svc.connect(
        playerId: playerId,
        displayName: displayName,
        roomCode: roomCode,
        boardSize: boardSize,
        maxPlayers: maxPlayers,
      );
    } catch (e) {
      if (state.status == WiredStatus.waking) {
        state = state.copyWith(
            status: WiredStatus.error, errorMessage: 'CONNECTION_FAILED');
      }
      return;
    }

    // Transition waking → waiting is handled by _onLog('UPLINK_ESTABLISHED').
    // Only advance here if the first try succeeded synchronously and the
    // log handler hasn't already moved us to waiting.
    if (state.status == WiredStatus.waking) {
      state = state.copyWith(status: WiredStatus.waiting);
    }
  }

  /// Sends a startGame request to the server (host only; ≥ 2 players required).
  void startGame() {
    _transport?.sendAction(GameMessage(
      type: MessageType.startGame,
      playerId: state.localPlayerId,
      roomId: state.roomCode,
    ));
  }

  // ── Client ────────────────────────────────────────────────────────────────

  /// Joins an existing room by code.
  Future<void> joinWithCode({
    required String roomCode,
    required String playerId,
    required String displayName,
  }) async {
    await _reset();
    final svc = WiredServerService();
    _transport = svc;

    state = WiredGameState(
      status: WiredStatus.waking,
      role: WiredRole.client,
      localPlayerId: playerId,
      roomCode: roomCode.toUpperCase(),
    );

    _subscribeToTransport();

    try {
      await svc.connect(
        playerId: playerId,
        displayName: displayName,
        roomCode: roomCode.toUpperCase(),
      );
    } catch (e) {
      if (state.status == WiredStatus.waking) {
        state = state.copyWith(
            status: WiredStatus.error, errorMessage: 'CONNECTION_FAILED');
      }
      return;
    }

    if (state.status == WiredStatus.waking) {
      state = state.copyWith(status: WiredStatus.waiting);
    }
  }

  // ── Game actions ──────────────────────────────────────────────────────────

  void placeStone(Position pos) {
    _transport?.sendAction(GameMessage.placeStone(
      playerId: state.localPlayerId,
      roomId: state.roomCode,
      pos: pos,
    ));
  }

  void pass() {
    _transport?.sendAction(
        GameMessage.pass(playerId: state.localPlayerId, roomId: state.roomCode));
  }

  void launchAttack(AttackAction action) {
    _transport?.sendAction(
        GameMessage.performAttack(roomId: state.roomCode, action: action));
  }

  // ── Subscriptions ─────────────────────────────────────────────────────────

  void _subscribeToTransport() {
    final t = _transport!;
    _subs.add(t.stateStream.listen(_onGameState));
    _subs.add(t.logStream.listen(_onLog));
    _subs.add(t.errorStream.listen(_onError));
    _subs.add(t.playerListStream.listen(_onPlayerList));
  }

  void _onLog(String line) {
    _addLog(line);
  }

  void _onGameState(GameState gs) {
    final isOver =
        gs.phase == GamePhase.finished || gs.phase == GamePhase.scoring;
    state = state.copyWith(
      status: isOver ? WiredStatus.over : WiredStatus.playing,
      gameState: gs,
    );
  }

  void _onPlayerList(List<ConnectedPlayer> players) {
    state = state.copyWith(connectedPlayers: players);
  }

  void _onError(String msg) {
    // A small set of codes are fatal and must surface even during gameplay.
    const fatalDuringPlay = {
      'SERVER_DISCONNECTED',
      'ROOM_NOT_FOUND',
      'VERSION_MISMATCH',
      'ROOM_FULL',
    };
    // Ignore non-fatal server errors during gameplay.
    if (state.status == WiredStatus.playing &&
        !fatalDuringPlay.contains(msg)) {
      _addLog('SERVER_ERROR: $msg');
      return;
    }
    // Server is in sleep mode (cold start) — service is auto-retrying.
    if (msg == 'WAKING_UP') {
      state = state.copyWith(status: WiredStatus.waking);
      return;
    }
    state = state.copyWith(status: WiredStatus.error, errorMessage: msg);
    _addLog('ERROR: $msg');
  }

  void _addLog(String line) {
    final ts = DateTime.now();
    final stamp =
        '[${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}]';
    final newLines = [...state.logLines, '$stamp $line'];
    state = state.copyWith(
      logLines: newLines.length > _maxLogLines
          ? newLines.sublist(newLines.length - _maxLogLines)
          : newLines,
    );
  }

  // ── Reset / leave ─────────────────────────────────────────────────────────

  Future<void> _reset() async {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    await _transport?.dispose();
    _transport = null;
    state = const WiredGameState();
  }

  /// Sends a chat message to the server (Wired only; no-op on other transports).
  void sendChatMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final t = _transport;
    if (t is WiredServerService) t.sendChatMessage(trimmed);
  }

  Future<void> leave() => _reset();
}

// ── Provider ──────────────────────────────────────────────────────────────

final wiredGameProvider =
    NotifierProvider<WiredGameNotifier, WiredGameState>(WiredGameNotifier.new);

