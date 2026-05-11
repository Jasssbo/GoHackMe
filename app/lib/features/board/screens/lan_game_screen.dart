import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/cyberpunk_colors.dart';
import '../../../core/widgets/glitch_overlay.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/lan_game_provider.dart';
import '../../../services/lan_discovery_service.dart';
import '../../../services/lan_player.dart';
import '../widgets/game_layout.dart';

// ── LanGameScreen ─────────────────────────────────────────────────────────

/// LAN multiplayer game screen used by both host and client.
///
/// If [room] is null the device is the host; [boardSize] and [maxPlayers]
/// are used to start the server.  If [room] is provided the device is a
/// client that joins the discovered room.
class LanGameScreen extends ConsumerStatefulWidget {
  /// Non-null when acting as a client.
  final LanRoom? room;
  /// Used only when hosting.
  final int boardSize;
  final int maxPlayers;

  const LanGameScreen({
    super.key,
    this.room,
    this.boardSize = 19,
    this.maxPlayers = 2,
  });

  @override
  ConsumerState<LanGameScreen> createState() => _LanGameScreenState();
}

class _LanGameScreenState extends ConsumerState<LanGameScreen> {
  Position? _lastPlaced;
  final _attackGlitch = ValueNotifier<int>(0);

  bool get _isHost => widget.room == null;

  @override
  void dispose() {
    _attackGlitch.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final auth = ref.read(authProvider).valueOrNull;
    final playerId = auth?.playerId ?? 'player_${DateTime.now().millisecondsSinceEpoch}';
    final rawName = auth?.displayName ?? '';
    final displayName = rawName.isNotEmpty ? rawName.toUpperCase() : 'ANONYMOUS';
    final notifier = ref.read(lanGameProvider.notifier);

    if (_isHost) {
      await notifier.startAsHost(
        playerId: playerId,
        displayName: displayName,
        boardSize: widget.boardSize,
        maxPlayers: widget.maxPlayers,
      );
    } else {
      await notifier.joinRoom(
        room: widget.room!,
        playerId: playerId,
        displayName: displayName,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lanState = ref.watch(lanGameProvider);

    return Scaffold(
      backgroundColor: CyberpunkColors.background,
      body: GlitchOverlay(
        burstSignal: _attackGlitch,
        child: _buildBody(context, lanState),
      ),
    );
  }

  Widget _buildBody(BuildContext context, LanGameState ls) {
    switch (ls.status) {
      case LanGameStatus.idle:
        return const _BootScreen();

      case LanGameStatus.error:
        return _ErrorPanel(
          message: ls.errorMessage ?? 'UNKNOWN_ERROR',
          onBack: () => context.go(Routes.lobby),
        );

      case LanGameStatus.waiting:
        return _WaitingPanel(
          isHost: _isHost,
          roomCode: ls.roomCode,
          players: ls.connectedPlayers,
          maxPlayers: ls.maxPlayers,
          logLines: ls.logLines,
          onStart: _isHost ? () => ref.read(lanGameProvider.notifier).startGameNow() : null,
          onBack: () => context.go(Routes.lobby),
        );

      case LanGameStatus.over:
        return _GameOverPanel(
          state: ls.gameState!,
          logLines: ls.logLines,
          onBack: () => context.go(Routes.lobby),
        );

      case LanGameStatus.playing:
        final gs = ls.gameState!;
        return GameLayout(
          state: gs,
          localPlayerId: ls.localPlayerId,
          statusLabel: 'WIRED:${ls.roomCode}',
          attackBurst: _attackGlitch,
          logLines: ls.logLines,
          lastPlaced: _lastPlaced,
          onExit: () {
            ref.read(lanGameProvider.notifier).leave();
            context.go(Routes.lobby);
          },
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
  }
}

// ── _BootScreen ────────────────────────────────────────────────────────────

class _BootScreen extends StatelessWidget {
  const _BootScreen();
  @override
  Widget build(BuildContext context) => const Center(
        child: Text(
          'ʕ•ᴥ•ʔ',
          style: TextStyle(
            color: CyberpunkColors.green,
            fontSize: 28,
            fontFamily: 'monospace',
          ),
        ),
      );
}

// ── _ErrorPanel ────────────────────────────────────────────────────────────

class _ErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback onBack;
  const _ErrorPanel({required this.message, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'CONNECTION_FAILED',
              style: const TextStyle(
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

// ── _WaitingPanel ──────────────────────────────────────────────────────────

class _WaitingPanel extends StatelessWidget {
  final bool isHost;
  final String roomCode;
  final List<LanPlayer> players;
  final int maxPlayers;
  final List<String> logLines;
  final VoidCallback? onStart;
  final VoidCallback onBack;

  const _WaitingPanel({
    required this.isHost,
    required this.roomCode,
    required this.players,
    required this.maxPlayers,
    required this.logLines,
    required this.onStart,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              isHost ? '// WIRED_HOST.sh' : '// WIRED_CLIENT.sh',
              style: const TextStyle(
                color: CyberpunkColors.cyan,
                fontSize: 18,
                letterSpacing: 3,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            // Room code
            Row(
              children: [
                const Text(
                  'ROOM: ',
                  style: TextStyle(
                    color: CyberpunkColors.textDim,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  roomCode,
                  style: const TextStyle(
                    color: CyberpunkColors.yellow,
                    fontSize: 22,
                    letterSpacing: 6,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (isHost)
              const Text(
                'Share your WiFi / hotspot — nearby devices scan for WIRED rooms automatically.',
                style: TextStyle(
                  color: CyberpunkColors.textDim,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            const SizedBox(height: 24),

            // Player list
            Text(
              '// WIRED_NODES (${players.length}/$maxPlayers)',
              style: const TextStyle(
                color: CyberpunkColors.cyanDim,
                fontSize: 10,
                letterSpacing: 2,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            ...players.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Text('▶ ',
                        style:
                            TextStyle(color: CyberpunkColors.green, fontSize: 10)),
                    Text(
                      p.displayName,
                      style: const TextStyle(
                        color: CyberpunkColors.textPrimary,
                        fontSize: 11,
                        letterSpacing: 1,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (players.length < maxPlayers)
              Row(
                children: [
                  if (players.length < 2) ...[    
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        color: CyberpunkColors.cyanDim,
                        strokeWidth: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Waiting for ${2 - players.length} more node(s) to wire in…',
                      style: const TextStyle(
                        color: CyberpunkColors.textDim,
                        fontSize: 9,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ] else
                    Text(
                      'Ready to start — up to ${maxPlayers - players.length} more node(s) can still join.',
                      style: const TextStyle(
                        color: CyberpunkColors.green,
                        fontSize: 9,
                        fontFamily: 'monospace',
                      ),
                    ),
                ],
              ),

            const Spacer(),

            // Log tail
            if (logLines.isNotEmpty)
              Container(
                height: 80,
                color: const Color(0xFF030810),
                padding: const EdgeInsets.all(6),
                child: ListView.builder(
                  reverse: true,
                  itemCount: logLines.length,
                  itemBuilder: (_, i) => Text(
                    logLines[logLines.length - 1 - i],
                    style: const TextStyle(
                      color: CyberpunkColors.green,
                      fontSize: 8,
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Buttons
            if (isHost && onStart != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: players.length >= 2 ? onStart : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          CyberpunkColors.green.withValues(alpha: 0.15),
                      foregroundColor: CyberpunkColors.green,
                      side:
                          const BorderSide(color: CyberpunkColors.green),
                    ),
                    child: const Text('START_GAME.sh'),
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(
                  foregroundColor: CyberpunkColors.textDim,
                  side: BorderSide(
                    color: CyberpunkColors.textDim.withValues(alpha: 0.4),
                  ),
                ),
                child: const Text('ABORT'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _GameOverPanel ─────────────────────────────────────────────────────────

class _GameOverPanel extends StatelessWidget {
  final GameState state;
  final List<String> logLines;
  final VoidCallback onBack;

  const _GameOverPanel({
    required this.state,
    required this.logLines,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final colorScores = Scorer.areaScore(state.board); // Map<StoneColor, int>
    // Map each player to their score via their positional StoneColor
    int scoreOf(Player p) {
      final idx = state.players.indexOf(p);
      return colorScores[StoneColor.fromIndex(idx)] ?? 0;
    }
    final sorted = [...state.players]
      ..sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '// GAME_OVER.log',
              style: TextStyle(
                color: CyberpunkColors.error,
                fontSize: 20,
                letterSpacing: 4,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '> FINAL_SCORES:',
              style: TextStyle(
                color: CyberpunkColors.cyanDim,
                fontSize: 10,
                letterSpacing: 2,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            ...sorted.asMap().entries.map((e) {
              final rank = e.key + 1;
              final p = e.value;
              final score = scoreOf(p);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '#$rank  ${p.displayName.padRight(16)} $score pts',
                  style: TextStyle(
                    color: rank == 1
                        ? CyberpunkColors.yellow
                        : CyberpunkColors.textSecondary,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    letterSpacing: 1,
                  ),
                ),
              );
            }),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onBack,
                child: const Text('BACK_TO_LOBBY'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
