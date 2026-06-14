import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';
import 'package:uuid/uuid.dart';

import '../../../services/i_game_transport.dart';
import '../../../services/lan_discovery_service.dart';
import '../../../services/lan_host_service.dart';
import '../../../services/lan_client_service.dart';
import '../../../services/connected_player.dart';

// ── LAN role ───────────────────────────────────────────────────────────────

enum LanRole { host, client }

// ── LanGameStatus ─────────────────────────────────────────────────────────

/// Phase of the LAN session from the app's perspective.
enum LanGameStatus {
  /// Nothing started.
  idle,
  /// Host: server started, broadcasting, waiting for players.
  /// Client: connected to host, waiting for host to start.
  waiting,
  /// Game is in progress.
  playing,
  /// Game finished (final scoring phase or finished).
  over,
  /// A network or protocol error occurred.
  error,
}

// ── LanGameState ──────────────────────────────────────────────────────────

class LanGameState {
  final LanGameStatus status;
  final LanRole? role;
  final GameState? gameState;
  final List<String> logLines;
  final String localPlayerId;
  final String roomCode;
  final List<ConnectedPlayer> connectedPlayers; // host waiting room
  final int maxPlayers;
  final String? errorMessage;

  const LanGameState({
    this.status = LanGameStatus.idle,
    this.role,
    this.gameState,
    this.logLines = const [],
    this.localPlayerId = '',
    this.roomCode = '',
    this.connectedPlayers = const [],
    this.maxPlayers = 2,
    this.errorMessage,
  });

  LanGameState copyWith({
    LanGameStatus? status,
    LanRole? role,
    GameState? gameState,
    List<String>? logLines,
    String? localPlayerId,
    String? roomCode,
    List<ConnectedPlayer>? connectedPlayers,
    int? maxPlayers,
    String? errorMessage,
  }) =>
      LanGameState(
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

// ── LanGameNotifier ───────────────────────────────────────────────────────

class LanGameNotifier extends Notifier<LanGameState> {
  static const _maxLogLines = 60;

  /// Unified transport — set to whichever concrete service is active.
  /// Using [IGameTransport] eliminates host/client branching in action methods
  /// (DIP: high-level policy depends on abstraction, not on concrete details).
  IGameTransport? _transport;

  /// Host-only reference, kept solely for the [startGameNow] call.
  LanHostService? _hostService;

  final List<StreamSubscription> _subs = [];

  @override
  LanGameState build() {
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
      _transport?.dispose();
    });
    return const LanGameState();
  }

  // ── Host setup ────────────────────────────────────────────────────────────

  Future<void> startAsHost({
    required String playerId,
    required String displayName,
    required int boardSize,
    required int maxPlayers,
  }) async {
    await _reset();

    final roomCode = const Uuid().v4().substring(0, 8).toUpperCase();
    final svc = LanHostService();
    _hostService = svc;
    _transport = svc;

    try {
      await svc.startServer(
        roomCode: roomCode,
        hostPlayerId: playerId,
        hostDisplayName: displayName,
        boardSize: boardSize,
        maxPlayers: maxPlayers,
      );
    } catch (e) {
      state = LanGameState(
        status: LanGameStatus.error,
        errorMessage: 'HOST_START_FAILED: $e',
      );
      return;
    }

    state = LanGameState(
      status: LanGameStatus.waiting,
      role: LanRole.host,
      localPlayerId: playerId,
      roomCode: roomCode,
      connectedPlayers: svc.players,
      maxPlayers: maxPlayers,
    );

    _subscribeToTransport();
  }

  /// Host-only: manually start the game before all slots are filled.
  void startGameNow() {
    _hostService?.startGame();
  }

  // ── Client setup ──────────────────────────────────────────────────────────

  Future<void> joinRoom({
    required LanRoom room,
    required String playerId,
    required String displayName,
  }) async {
    await _reset();

    final svc = LanClientService();
    _transport = svc;

    state = LanGameState(
      status: LanGameStatus.waiting,
      role: LanRole.client,
      localPlayerId: playerId,
      roomCode: room.roomCode,
      maxPlayers: room.maxPlayers,
    );

    _subscribeToTransport();

    try {
      await svc.connect(
        hostAddress: room.hostAddress,
        tcpPort: room.tcpPort,
        playerId: playerId,
        displayName: displayName,
        roomCode: room.roomCode,
      );
    } catch (e) {
      state = state.copyWith(
        status: LanGameStatus.error,
        errorMessage: 'CONNECT_FAILED: $e',
      );
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

  // ── Stream subscriptions ──────────────────────────────────────────────────

  /// Subscribe to all [IGameTransport] streams uniformly.
  ///
  /// Both host and client expose the same interface — no role-branching
  /// needed here (ISP + DIP payoff).
  void _subscribeToTransport() {
    final t = _transport!;
    _subs.add(t.stateStream.listen(_onGameState));
    _subs.add(t.logStream.listen(_addLog));
    _subs.add(t.errorStream.listen(_onError));
    _subs.add(t.playerListStream.listen(_onPlayerList));
  }

  // ── Stream callbacks ──────────────────────────────────────────────────────

  void _onGameState(GameState gs) {
    final isOver =
        gs.phase == GamePhase.finished || gs.phase == GamePhase.scoring;
    state = state.copyWith(
      status: isOver ? LanGameStatus.over : LanGameStatus.playing,
      gameState: gs,
    );
  }

  void _onPlayerList(List<ConnectedPlayer> players) {
    state = state.copyWith(connectedPlayers: players);
  }

  void _onError(String msg) {
    state = state.copyWith(
      status: LanGameStatus.error,
      errorMessage: msg,
    );
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

  // ── Reset / dispose ───────────────────────────────────────────────────────

  Future<void> _reset() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _transport?.dispose();
    _transport = null;
    _hostService = null;
    state = const LanGameState(); // clears logLines along with everything else
  }

  /// Disconnect and clear all state (including logs). Call before navigating away.
  Future<void> leave() => _reset();
}

final lanGameProvider =
    NotifierProvider<LanGameNotifier, LanGameState>(LanGameNotifier.new);
