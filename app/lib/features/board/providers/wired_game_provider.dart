import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';
import 'package:uuid/uuid.dart';

import '../../../services/i_game_transport.dart';
import '../../../services/lan_player.dart';
import '../../../services/wired_host_service.dart';
import '../../../services/wired_client_service.dart';

// ── WiredRole ─────────────────────────────────────────────────────────────

enum WiredRole { host, client }

// ── WiredStatus ───────────────────────────────────────────────────────────

enum WiredStatus {
  /// Nothing initialised.
  idle,
  /// Host/client: negotiating WebRTC connection.
  connecting,
  /// Waiting for host to start (lobby phase).
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
  final List<LanPlayer> connectedPlayers;
  final int maxPlayers;
  final String? errorMessage;

  /// True while [WiredGameNotifier.joinWithCode] is in progress.
  final bool isConnecting;

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
    this.isConnecting = false,
  });

  WiredGameState copyWith({
    WiredStatus? status,
    WiredRole? role,
    GameState? gameState,
    List<String>? logLines,
    String? localPlayerId,
    String? roomCode,
    List<LanPlayer>? connectedPlayers,
    int? maxPlayers,
    String? errorMessage,
    bool? isConnecting,
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
        isConnecting: isConnecting ?? this.isConnecting,
      );
}

// ── WiredGameNotifier ─────────────────────────────────────────────────────

class WiredGameNotifier extends Notifier<WiredGameState> {
  static const _maxLogLines = 60;

  IGameTransport? _transport;
  WiredHostService? _hostService;
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

  // ── Host setup ────────────────────────────────────────────────────────────

  void openAsHost({
    required String playerId,
    required String displayName,
    required int boardSize,
    required int maxPlayers,
  }) {
    _reset();
    final roomCode = const Uuid().v4().substring(0, 6).toUpperCase();
    final svc = WiredHostService();
    _hostService = svc;
    _transport = svc;

    svc.open(
      roomCode: roomCode,
      hostPlayerId: playerId,
      hostDisplayName: displayName,
      boardSize: boardSize,
      maxPlayers: maxPlayers,
    );

    state = WiredGameState(
      status: WiredStatus.waiting,
      role: WiredRole.host,
      localPlayerId: playerId,
      roomCode: roomCode,
      connectedPlayers: svc.players,
      maxPlayers: maxPlayers,
    );

    _subscribeToTransport();

    // Also subscribe to host-specific status events.
    _subs.add(svc.statusStream.listen(_onHostStatus));
  }

  /// Starts the game (host only, ≥ 2 players required).
  void startGame() => _hostService?.startGame();

  // ── Client setup ──────────────────────────────────────────────────────────

  /// Connects as a client using the host's 6-char room code.
  Future<void> joinWithCode({
    required String roomCode,
    required String playerId,
    required String displayName,
  }) async {
    _reset();
    final svc = WiredClientService();
    _transport = svc;

    state = WiredGameState(
      status: WiredStatus.connecting,
      role: WiredRole.client,
      localPlayerId: playerId,
      roomCode: roomCode.toUpperCase(),
    );

    _subscribeToTransport();

    final ok = await svc.connectWithCode(
      roomCode: roomCode.toUpperCase(),
      playerId: playerId,
      displayName: displayName,
    );

    if (!ok) {
      state = state.copyWith(
        status: WiredStatus.error,
        errorMessage: 'FAILED_TO_CONNECT — invalid or expired room code',
      );
      return;
    }

    state = state.copyWith(status: WiredStatus.waiting);
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
    _subs.add(t.logStream.listen(_addLog));
    _subs.add(t.errorStream.listen(_onError));
    _subs.add(t.playerListStream.listen(_onPlayerList));
  }

  void _onGameState(GameState gs) {
    final isOver =
        gs.phase == GamePhase.finished || gs.phase == GamePhase.scoring;
    state = state.copyWith(
      status: isOver ? WiredStatus.over : WiredStatus.playing,
      gameState: gs,
    );
  }

  void _onPlayerList(List<LanPlayer> players) {
    state = state.copyWith(connectedPlayers: players);
  }

  void _onError(String msg) {
    state = state.copyWith(
      status: WiredStatus.error,
      errorMessage: msg,
    );
    _addLog('ERROR: $msg');
  }

  void _onHostStatus(String event) {
    // Forward meaningful host-side events as log lines.
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

  // ── Reset ─────────────────────────────────────────────────────────────────

  void _reset() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _transport?.dispose();
    _transport = null;
    _hostService = null;
    state = const WiredGameState();
  }

  Future<void> leave() async {
    _reset();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────

final wiredGameProvider =
    NotifierProvider<WiredGameNotifier, WiredGameState>(WiredGameNotifier.new);
