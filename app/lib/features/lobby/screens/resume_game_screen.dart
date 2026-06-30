import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/cyberpunk_colors.dart';
import '../../../core/widgets/glitch_overlay.dart';
import '../../auth/providers/auth_provider.dart';
import '../../board/providers/wired_game_provider.dart';
import '../../board/providers/lan_game_provider.dart';
import '../../board/widgets/game_layout.dart';
import '../../../services/saved_game_service.dart';
import '../widgets/resume_game_dialog.dart';

// ── ResumeGameMode ────────────────────────────────────────────────────────

enum ResumeGameMode { lan, wired }

// ── ResumeGameScreen ──────────────────────────────────────────────────────

/// Host-side screen that opens a new room seeded with a [SavedGame].
///
/// After the room is ready the host is already assigned to [SavedGame.saverPlayerIndex].
/// Other players join normally and — for 3/4-player games — are shown the
/// [PlayerSlotPickerDialog] to claim their slot.
class ResumeGameScreen extends ConsumerStatefulWidget {
  final SavedGame save;
  final ResumeGameMode mode;

  const ResumeGameScreen({
    super.key,
    required this.save,
    required this.mode,
  });

  @override
  ConsumerState<ResumeGameScreen> createState() => _ResumeGameScreenState();
}

class _ResumeGameScreenState extends ConsumerState<ResumeGameScreen> {
  Position? _lastPlaced;
  final _attackGlitch = ValueNotifier<int>(0);
  bool _restoreSent = false;

  @override
  void dispose() {
    _attackGlitch.dispose();
    if (widget.mode == ResumeGameMode.wired) {
      ref.read(wiredGameProvider.notifier).leave();
    } else {
      ref.read(lanGameProvider.notifier).leave();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final auth = ref.read(authProvider).valueOrNull;
    final playerId = auth?.playerId ?? const Uuid().v4();
    final rawName = auth?.displayName ?? '';
    final displayName = rawName.isNotEmpty ? rawName.toUpperCase() : 'ANONYMOUS';
    final save = widget.save;
    final totalPlayers = save.state.players.length;

    if (widget.mode == ResumeGameMode.wired) {
      await ref.read(wiredGameProvider.notifier).openAsHost(
            playerId: playerId,
            displayName: displayName,
            boardSize: save.boardSize,
            maxPlayers: totalPlayers,
          );
    } else {
      await ref.read(lanGameProvider.notifier).startAsHost(
            playerId: playerId,
            displayName: displayName,
            boardSize: save.boardSize,
            maxPlayers: totalPlayers,
          );
    }
  }

  /// Sends the restoreGame message once the transport is ready.
  void _sendRestore() {
    if (_restoreSent) return;
    _restoreSent = true;
    if (widget.mode == ResumeGameMode.wired) {
      ref.read(wiredGameProvider.notifier).restoreGame(
            widget.save.state,
            widget.save.saverPlayerIndex,
          );
    } else {
      ref.read(lanGameProvider.notifier).restoreGame(
            widget.save.state,
            widget.save.saverPlayerIndex,
          );
    }
  }

  Future<void> _saveGame(GameState gs, String localPlayerId) async {
    final playerIdx = gs.players.indexWhere((p) => p.id == localPlayerId);
    final saverIdx = playerIdx >= 0 ? playerIdx : widget.save.saverPlayerIndex;
    await SavedGameService.save(
      state: gs,
      saverPlayerIndex: saverIdx,
      label: widget.save.label,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('GAME_SAVED  ·  resume from lobby',
          style: TextStyle(fontFamily: 'monospace')),
      duration: Duration(seconds: 2),
      backgroundColor: Color(0xFF0D2B1A),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == ResumeGameMode.wired) {
      return _buildWired(context);
    } else {
      return _buildLan(context);
    }
  }

  // ── Wired build ───────────────────────────────────────────────────────────

  Widget _buildWired(BuildContext context) {
    final ws = ref.watch(wiredGameProvider);

    // Send restoreGame as soon as we are in waiting phase.
    if (ws.status == WiredStatus.waiting && !_restoreSent) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sendRestore());
    }

    return Scaffold(
      backgroundColor: const Color(0xFF06040F),
      body: GlitchOverlay(
        burstSignal: _attackGlitch,
        child: _buildWiredBody(context, ws),
      ),
    );
  }

  Widget _buildWiredBody(BuildContext context, WiredGameState ws) {
    switch (ws.status) {
      case WiredStatus.idle:
      case WiredStatus.connecting:
      case WiredStatus.waking:
        return const _ResumeBootScreen();

      case WiredStatus.waiting:
        return _ResumeWaitingPanel(
          save: widget.save,
          roomCode: ws.roomCode,
          connectedCount: ws.connectedPlayers.length,
          onBack: () {
            ref.read(wiredGameProvider.notifier).leave();
            context.go(Routes.lobby);
          },
        );

      case WiredStatus.playing:
        final gs = ws.gameState!;
        return GameLayout(
          state: gs,
          localPlayerId: ws.localPlayerId,
          statusLabel: 'THE_WIRED:${ws.roomCode}',
          attackBurst: _attackGlitch,
          logLines: ws.logLines,
          lastPlaced: _lastPlaced,
          serverTurnStartedAt: ws.serverTurnStartedAt,
          onExit: () {
            ref.read(wiredGameProvider.notifier).leave();
            context.go(Routes.lobby);
          },
          onPass: () => ref.read(wiredGameProvider.notifier).pass(),
          onSave: () => _saveGame(gs, ws.localPlayerId),
          onPlace: (pos) {
            setState(() => _lastPlaced = pos);
            ref.read(wiredGameProvider.notifier).placeStone(pos);
          },
          onAttack: (action) {
            _attackGlitch.value++;
            ref.read(wiredGameProvider.notifier).launchAttack(action);
          },
          onChatSend: (text) =>
              ref.read(wiredGameProvider.notifier).sendChatMessage(text),
        );

      case WiredStatus.over:
        return _ResumeGameOverPanel(
          state: ws.gameState!,
          onBack: () {
            ref.read(wiredGameProvider.notifier).leave();
            context.go(Routes.lobby);
          },
        );

      case WiredStatus.error:
        return _ResumeErrorPanel(
          message: ws.errorMessage ?? 'UNKNOWN_ERROR',
          onBack: () {
            ref.read(wiredGameProvider.notifier).leave();
            context.go(Routes.lobby);
          },
        );
    }
  }

  // ── LAN build ─────────────────────────────────────────────────────────────

  Widget _buildLan(BuildContext context) {
    final ls = ref.watch(lanGameProvider);

    // Send restoreGame as soon as we are in waiting phase.
    if (ls.status == LanGameStatus.waiting && !_restoreSent) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sendRestore());
    }

    return Scaffold(
      backgroundColor: CyberpunkColors.background,
      body: GlitchOverlay(
        burstSignal: _attackGlitch,
        child: _buildLanBody(context, ls),
      ),
    );
  }

  Widget _buildLanBody(BuildContext context, LanGameState ls) {
    switch (ls.status) {
      case LanGameStatus.idle:
        return const _ResumeBootScreen();

      case LanGameStatus.error:
        return _ResumeErrorPanel(
          message: ls.errorMessage ?? 'UNKNOWN_ERROR',
          onBack: () {
            ref.read(lanGameProvider.notifier).leave();
            context.go(Routes.lobby);
          },
        );

      case LanGameStatus.waiting:
        return _ResumeWaitingPanel(
          save: widget.save,
          roomCode: ls.roomCode,
          connectedCount: ls.connectedPlayers.length,
          onBack: () {
            ref.read(lanGameProvider.notifier).leave();
            context.go(Routes.lobby);
          },
        );

      case LanGameStatus.over:
        return _ResumeGameOverPanel(
          state: ls.gameState!,
          onBack: () {
            ref.read(lanGameProvider.notifier).leave();
            context.go(Routes.lobby);
          },
        );

      case LanGameStatus.playing:
        final gs = ls.gameState!;
        return GameLayout(
          state: gs,
          localPlayerId: ls.localPlayerId,
          statusLabel: 'LAN:${ls.roomCode}',
          attackBurst: _attackGlitch,
          logLines: ls.logLines,
          lastPlaced: _lastPlaced,
          onExit: () {
            ref.read(lanGameProvider.notifier).leave();
            context.go(Routes.lobby);
          },
          onPass: () => ref.read(lanGameProvider.notifier).pass(),
          onSave: () => _saveGame(gs, ls.localPlayerId),
          onPlace: (pos) {
            setState(() => _lastPlaced = pos);
            ref.read(lanGameProvider.notifier).placeStone(pos);
          },
          onAttack: (action) {
            _attackGlitch.value++;
            ref.read(lanGameProvider.notifier).launchAttack(action);
          },
        );
    }
  }
}

// ── JoinResumeScreen ──────────────────────────────────────────────────────

/// Client-side join screen for a restore room with ≥ 3 players.
///
/// The joining player selects which slot they occupied in the saved game.
/// For 2-player saves the slot is auto-assigned by the server; this widget
/// is only shown when [save.playerCount] > 2.
class JoinResumeScreen extends ConsumerStatefulWidget {
  final SavedGame save;
  final ResumeGameMode mode;

  /// For wired: the room code shared by the host.
  final String roomCode;

  /// The host's slot index (already claimed; greyed out in the picker).
  final int hostSlotIndex;

  const JoinResumeScreen({
    super.key,
    required this.save,
    required this.mode,
    required this.roomCode,
    required this.hostSlotIndex,
  });

  @override
  ConsumerState<JoinResumeScreen> createState() => _JoinResumeScreenState();
}

class _JoinResumeScreenState extends ConsumerState<JoinResumeScreen> {
  Position? _lastPlaced;
  final _attackGlitch = ValueNotifier<int>(0);
  bool _claimSent = false;

  @override
  void dispose() {
    _attackGlitch.dispose();
    if (widget.mode == ResumeGameMode.wired) {
      ref.read(wiredGameProvider.notifier).leave();
    } else {
      ref.read(lanGameProvider.notifier).leave();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // For 2-player saves, auto-claim is done by server; for ≥3 show picker.
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  Future<void> _connect() async {
    final auth = ref.read(authProvider).valueOrNull;
    final playerId = auth?.playerId ?? const Uuid().v4();
    final rawName = auth?.displayName ?? '';
    final displayName = rawName.isNotEmpty ? rawName.toUpperCase() : 'ANONYMOUS';

    if (widget.mode == ResumeGameMode.wired) {
      await ref.read(wiredGameProvider.notifier).joinWithCode(
            roomCode: widget.roomCode,
            playerId: playerId,
            displayName: displayName,
          );
    }
    // LAN join: handled differently (via discovery + LanJoinScreen flow).
  }

  void _claimSlot(int slotIndex) {
    if (_claimSent) return;
    _claimSent = true;
    if (widget.mode == ResumeGameMode.wired) {
      ref.read(wiredGameProvider.notifier).claimSlot(slotIndex);
    } else {
      ref.read(lanGameProvider.notifier).claimSlot(slotIndex);
    }
  }

  Future<void> _saveGame(GameState gs, String localPlayerId) async {
    final playerIdx = gs.players.indexWhere((p) => p.id == localPlayerId);
    final saverIdx = playerIdx >= 0 ? playerIdx : 0;
    await SavedGameService.save(
      state: gs,
      saverPlayerIndex: saverIdx,
      label: widget.save.label,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('GAME_SAVED  ·  resume from lobby',
          style: TextStyle(fontFamily: 'monospace')),
      duration: Duration(seconds: 2),
      backgroundColor: Color(0xFF0D2B1A),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == ResumeGameMode.wired) {
      final ws = ref.watch(wiredGameProvider);
      return _buildScaffold(_buildWiredBody(context, ws));
    } else {
      final ls = ref.watch(lanGameProvider);
      return _buildScaffold(_buildLanBody(context, ls));
    }
  }

  Widget _buildScaffold(Widget body) => Scaffold(
        backgroundColor: CyberpunkColors.background,
        body: GlitchOverlay(burstSignal: _attackGlitch, child: body),
      );

  Widget _buildWiredBody(BuildContext context, WiredGameState ws) {
    if (ws.status == WiredStatus.waiting && !_claimSent && widget.save.playerCount > 2) {
      // Show player picker after connecting.
      WidgetsBinding.instance.addPostFrameCallback((_) => _showPicker());
    }
    return _buildCommonBody(
      context,
      gameState: ws.gameState,
      localPlayerId: ws.localPlayerId,
      logLines: ws.logLines,
      serverTurnStartedAt: ws.serverTurnStartedAt,
      isPlaying: ws.status == WiredStatus.playing,
      isOver: ws.status == WiredStatus.over,
      isError: ws.status == WiredStatus.error,
      errorMsg: ws.errorMessage,
      onPass: () => ref.read(wiredGameProvider.notifier).pass(),
      onPlace: (pos) {
        setState(() => _lastPlaced = pos);
        ref.read(wiredGameProvider.notifier).placeStone(pos);
      },
      onAttack: (action) {
        _attackGlitch.value++;
        ref.read(wiredGameProvider.notifier).launchAttack(action);
      },
      onChatSend: (text) =>
          ref.read(wiredGameProvider.notifier).sendChatMessage(text),
    );
  }

  Widget _buildLanBody(BuildContext context, LanGameState ls) {
    if (ls.status == LanGameStatus.waiting && !_claimSent && widget.save.playerCount > 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showPicker());
    }
    return _buildCommonBody(
      context,
      gameState: ls.gameState,
      localPlayerId: ls.localPlayerId,
      logLines: ls.logLines,
      isPlaying: ls.status == LanGameStatus.playing,
      isOver: ls.status == LanGameStatus.over,
      isError: ls.status == LanGameStatus.error,
      errorMsg: ls.errorMessage,
      onPass: () => ref.read(lanGameProvider.notifier).pass(),
      onPlace: (pos) {
        setState(() => _lastPlaced = pos);
        ref.read(lanGameProvider.notifier).placeStone(pos);
      },
      onAttack: (action) {
        _attackGlitch.value++;
        ref.read(lanGameProvider.notifier).launchAttack(action);
      },
    );
  }

  Widget _buildCommonBody(
    BuildContext context, {
    required GameState? gameState,
    required String localPlayerId,
    required List<String> logLines,
    required bool isPlaying,
    required bool isOver,
    required bool isError,
    String? errorMsg,
    DateTime? serverTurnStartedAt,
    required VoidCallback onPass,
    required void Function(Position) onPlace,
    required void Function(AttackAction) onAttack,
    void Function(String)? onChatSend,
  }) {
    if (isError) {
      return _ResumeErrorPanel(
        message: errorMsg ?? 'UNKNOWN_ERROR',
        onBack: () => context.go(Routes.lobby),
      );
    }
    if (isOver && gameState != null) {
      return _ResumeGameOverPanel(
        state: gameState,
        onBack: () => context.go(Routes.lobby),
      );
    }
    if (isPlaying && gameState != null) {
      return GameLayout(
        state: gameState,
        localPlayerId: localPlayerId,
        statusLabel: 'RESUME:${widget.roomCode}',
        attackBurst: _attackGlitch,
        logLines: logLines,
        lastPlaced: _lastPlaced,
        serverTurnStartedAt: serverTurnStartedAt,
        onExit: () => context.go(Routes.lobby),
        onPass: onPass,
        onSave: () => _saveGame(gameState, localPlayerId),
        onPlace: onPlace,
        onAttack: onAttack,
        onChatSend: onChatSend,
      );
    }
    return const _ResumeBootScreen();
  }

  bool _pickerShown = false;

  void _showPicker() {
    if (_pickerShown || !mounted) return;
    _pickerShown = true;
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'pick',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 160),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: child,
      ),
      pageBuilder: (ctx, _, __) => PlayerSlotPickerDialog(
        players: widget.save.state.players,
        claimedSlots: {widget.hostSlotIndex},
        onClaim: _claimSlot,
      ),
    );
  }
}

// ── Small helper screens ──────────────────────────────────────────────────

class _ResumeBootScreen extends StatelessWidget {
  const _ResumeBootScreen();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
                color: CyberpunkColors.cyan, strokeWidth: 1.5),
            SizedBox(height: 16),
            Text(
              'ESTABLISHING_UPLINK...',
              style: TextStyle(
                color: CyberpunkColors.cyanDim,
                fontSize: 10,
                letterSpacing: 2,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
}

class _ResumeWaitingPanel extends StatelessWidget {
  final SavedGame save;
  final String roomCode;
  final int connectedCount;
  final VoidCallback onBack;

  const _ResumeWaitingPanel({
    required this.save,
    required this.roomCode,
    required this.connectedCount,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final totalPlayers = save.state.players.length;
    final needed = totalPlayers - connectedCount;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '// RESTORE_SESSION',
              style: TextStyle(
                color: CyberpunkColors.cyan,
                fontSize: 16,
                letterSpacing: 3,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              save.label,
              style: const TextStyle(
                color: CyberpunkColors.textSecondary,
                fontSize: 9,
                letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 24),
            Container(
              height: 1,
              color: CyberpunkColors.cyanDim.withValues(alpha: 0.18),
            ),
            const SizedBox(height: 20),
            const Text(
              'ROOM_CODE:',
              style: TextStyle(
                color: CyberpunkColors.textSecondary,
                fontSize: 9,
                letterSpacing: 2,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              roomCode,
              style: const TextStyle(
                color: CyberpunkColors.magenta,
                fontSize: 28,
                letterSpacing: 8,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              needed > 0
                  ? 'Waiting for $needed more ${needed == 1 ? 'player' : 'players'} to reconnect...'
                  : 'All players connected — restoring game...',
              style: const TextStyle(
                color: CyberpunkColors.textSecondary,
                fontSize: 10,
                letterSpacing: 1,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Original players:  ${save.state.players.map((p) => p.displayName).join('  ·  ')}',
              style: TextStyle(
                color: CyberpunkColors.cyanDim.withValues(alpha: 0.70),
                fontSize: 8.5,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onBack,
              child: const Text(
                '< BACK_TO_LOBBY',
                style: TextStyle(
                  color: CyberpunkColors.textDim,
                  fontSize: 9,
                  fontFamily: 'monospace',
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumeGameOverPanel extends StatelessWidget {
  final GameState state;
  final VoidCallback onBack;

  const _ResumeGameOverPanel({required this.state, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'GAME_OVER',
            style: TextStyle(
              color: CyberpunkColors.cyan,
              fontSize: 22,
              letterSpacing: 6,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onBack,
            child: const Text('< BACK_TO_LOBBY'),
          ),
        ],
      ),
    );
  }
}

class _ResumeErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback onBack;

  const _ResumeErrorPanel({required this.message, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'RESTORE_FAILED',
              style: TextStyle(
                color: CyberpunkColors.error,
                fontSize: 16,
                letterSpacing: 3,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                color: CyberpunkColors.textSecondary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onBack,
              child: const Text('< BACK_TO_LOBBY'),
            ),
          ],
        ),
      ),
    );
  }
}
