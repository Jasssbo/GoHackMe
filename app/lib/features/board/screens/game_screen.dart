import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';

import '../../../core/theme/cyberpunk_colors.dart';
import '../../../core/widgets/glitch_overlay.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/game_provider.dart';
import '../widgets/game_layout.dart';

// ── GameScreen ────────────────────────────────────────────────────────────

class GameScreen extends ConsumerStatefulWidget {
  final String roomId;
  final int boardSize;
  final int maxPlayers;
  final String serverUrl;

  const GameScreen({
    super.key,
    required this.roomId,
    this.boardSize = 19,
    this.maxPlayers = 2,
    this.serverUrl = 'ws://localhost:8080/ws',
  });

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  Position? _lastPlaced;
  final _attackGlitch = ValueNotifier<int>(0);

  @override
  void dispose() {
    _attackGlitch.dispose();
    super.dispose();
  }

  String get _localPlayerId =>
      ref.watch(authProvider).valueOrNull?.playerId ?? 'local_player';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = ref.read(authProvider).valueOrNull;
      ref.read(gameStateProvider.notifier).connect(
            serverUrl: widget.serverUrl,
            playerId: auth?.playerId ?? 'local_player',
            roomId: widget.roomId,
            displayName: auth?.displayName ?? 'ANONYMOUS',
            boardSize: widget.boardSize,
            maxPlayers: widget.maxPlayers,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final gameAsync = ref.watch(gameStateProvider);
    final logLines = ref.watch(gameLogProvider);

    return Scaffold(
      backgroundColor: CyberpunkColors.background,
      body: GlitchOverlay(
        burstSignal: _attackGlitch,
        child: gameAsync.when(
          loading: () => const _BootScreen(),
          error: (e, _) => _ErrorPanel(
            error: e.toString(),
            onRetry: () {
              final auth = ref.read(authProvider).valueOrNull;
              ref.read(gameStateProvider.notifier).connect(
                    serverUrl: widget.serverUrl,
                    playerId: auth?.playerId ?? 'local_player',
                    roomId: widget.roomId,
                    displayName: auth?.displayName ?? 'ANONYMOUS',
                    boardSize: widget.boardSize,
                    maxPlayers: widget.maxPlayers,
                  );
            },
          ),
          data: (state) => state == null
              ? _WaitingScreen(
                  roomId: widget.roomId,
                  maxPlayers: widget.maxPlayers,
                )
              : GameLayout(
                  state: state,
                  localPlayerId: _localPlayerId,
                  statusLabel: 'WIRED:${widget.roomId}',
                  attackBurst: _attackGlitch,
                  logLines: logLines,
                  lastPlaced: _lastPlaced,
                  onPlace: (pos) {
                    setState(() => _lastPlaced = pos);
                    ref.read(gameStateProvider.notifier).placeStone(
                          _localPlayerId,
                          widget.roomId,
                          pos,
                        );
                  },
                  onAttack: (action) {
                    _attackGlitch.value++;
                    ref.read(gameStateProvider.notifier).launchAttack(
                          widget.roomId,
                          action,
                        );
                  },
                ),
        ),
      ),
    );
  }
}


// ── Waiting screen ─────────────────────────────────────────────────────────

class _WaitingScreen extends StatelessWidget {
  final String roomId;
  final int maxPlayers;
  const _WaitingScreen({required this.roomId, required this.maxPlayers});

  @override
  Widget build(BuildContext context) {
    final needed = maxPlayers - 1;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '┌───────────────────────┐',
            style: _mono,
          ),
          const Text('│  AWAITING CONNECTIONS  │', style: _mono),
          const Text(
            '└───────────────────────┘',
            style: _mono,
          ),
          const SizedBox(height: 24),
          const CircularProgressIndicator(
            color: CyberpunkColors.cyan,
            strokeWidth: 1.5,
          ),
          const SizedBox(height: 24),
          Text(
            'ROOM_ID: $roomId',
            style: const TextStyle(
              color: CyberpunkColors.magenta,
              fontSize: 22,
              letterSpacing: 8,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Waiting for $needed ${needed == 1 ? 'player' : 'players'} to connect_',
            style: const TextStyle(
              color: CyberpunkColors.textSecondary,
              fontSize: 11,
              letterSpacing: 1.5,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  static const _mono = TextStyle(
    color: CyberpunkColors.cyanDim,
    fontSize: 11,
    letterSpacing: 1,
    fontFamily: 'monospace',
  );
}

// ── Boot / error screens ───────────────────────────────────────────────────

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: CyberpunkColors.cyan,
            strokeWidth: 1.5,
          ),
          SizedBox(height: 16),
          Text(
            'INIT_CONNECTION...',
            style: TextStyle(
              color: CyberpunkColors.cyan,
              letterSpacing: 4,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String error;
  final VoidCallback? onRetry;
  const _ErrorPanel({required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('╔══ CONNECTION_ERROR ══╗',
              style: TextStyle(
                  color: CyberpunkColors.error,
                  fontFamily: 'monospace',
                  fontSize: 11)),
          const SizedBox(height: 8),
          Text(
            error,
            style: const TextStyle(
              color: CyberpunkColors.textSecondary,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            InkWell(
              onTap: onRetry,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: CyberpunkColors.error),
                ),
                child: const Text(
                  '> RETRY_CONNECTION',
                  style: TextStyle(
                    color: CyberpunkColors.error,
                    fontFamily: 'monospace',
                    fontSize: 11,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
