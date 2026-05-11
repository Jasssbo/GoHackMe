import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';

import '../../../core/theme/cyberpunk_colors.dart';
import '../../../core/theme/ui_scale.dart';
import '../../../core/widgets/glitch_overlay.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/local_game_provider.dart';
import '../widgets/game_layout.dart';

// ── LocalGameScreen ───────────────────────────────────────────────────────

/// Single-player 1v1 screen where the human faces a local bot.
///
/// No WebSocket or server needed – the [LocalGameNotifier] drives the entire
/// game loop including the bot's turns.
class LocalGameScreen extends ConsumerStatefulWidget {
  final int boardSize;
  final BotDifficulty difficulty;

  const LocalGameScreen({
    super.key,
    this.boardSize = 9,
    this.difficulty = BotDifficulty.intermediate,
  });

  @override
  ConsumerState<LocalGameScreen> createState() => _LocalGameScreenState();
}

class _LocalGameScreenState extends ConsumerState<LocalGameScreen> {
  Position? _lastPlaced;
  final _attackGlitch = ValueNotifier<int>(0);

  @override
  void dispose() {
    _attackGlitch.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = ref.read(authProvider).valueOrNull;
      ref.read(localGameProvider.notifier).startGame(
            boardSize: widget.boardSize,
            difficulty: widget.difficulty,
            humanName: auth?.displayName.isNotEmpty == true
                ? auth!.displayName.toUpperCase()
                : 'PLAYER_1',
            botName: _botLabel(widget.difficulty),
          );
    });
  }

  static String _botLabel(BotDifficulty d) {
    switch (d) {
      case BotDifficulty.beginner:
        return 'BOT_v0.1';
      case BotDifficulty.intermediate:
        return 'BOT_v0.5';
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(localGameProvider);
    final logLines = ref.watch(localGameLogProvider);
    final notifier = ref.read(localGameProvider.notifier);

    return Scaffold(
      backgroundColor: CyberpunkColors.background,
      body: GlitchOverlay(
        burstSignal: _attackGlitch,
        child: gameState == null
            ? const _InitScreen()
            : gameState.phase == GamePhase.finished ||
                    gameState.phase == GamePhase.scoring
                ? _GameOverScreen(
                    state: gameState,
                    logLines: logLines,
                    onRestart: () => _restart(context),
                  )
                : GameLayout(
                    state: gameState,
                    localPlayerId: notifier.humanId,
                    statusLabel: 'CLOSED::CIRCUIT',
                    attackBurst: _attackGlitch,
                    logLines: logLines,
                    lastPlaced: _lastPlaced,
                    onExit: () {
                      ref.read(localGameLogProvider.notifier).clear();
                      Navigator.of(context).pop();
                    },
                    onPass: () => notifier.pass(),
                    onPlace: (pos) {
                      // Only accept input when it's the human's placement turn
                      if (gameState.currentPlayerId != notifier.humanId) {
                        return;
                      }
                      setState(() => _lastPlaced = pos);
                      notifier.placeStone(pos);
                    },
                    onAttack: (action) {
                      _attackGlitch.value++;
                      notifier.launchAttack(action);
                    },
                  ),
      ),
    );
  }

  void _restart(BuildContext context) {
    final auth = ref.read(authProvider).valueOrNull;
    ref.read(localGameProvider.notifier).startGame(
          boardSize: widget.boardSize,
          difficulty: widget.difficulty,
          humanName: auth?.displayName.isNotEmpty == true
              ? auth!.displayName.toUpperCase()
              : 'PLAYER_1',
          botName: _botLabel(widget.difficulty),
        );
  }
}

// ── Init screen ────────────────────────────────────────────────────────────

class _InitScreen extends StatelessWidget {
  const _InitScreen();

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
            'LOADING_LOCAL_ENGINE...',
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

// ── Game-over screen ───────────────────────────────────────────────────────

class _GameOverScreen extends StatelessWidget {
  final GameState state;
  final List<String> logLines;
  final VoidCallback onRestart;

  const _GameOverScreen({
    required this.state,
    required this.logLines,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final scores = Scorer.areaScore(state.board);

    // Map player index → score
    final playerScores = [
      for (int i = 0; i < state.players.length; i++)
        (player: state.players[i], score: scores[StoneColor.fromIndex(i)] ?? 0),
    ];
    playerScores.sort((a, b) => b.score.compareTo(a.score));
    final winner = playerScores.first;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.s(400)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF050D15),
            border: Border.all(color: CyberpunkColors.cyanDim),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '╔══ GAME_OVER.log ══╗',
                style: TextStyle(
                  color: CyberpunkColors.cyan,
                  fontSize: 14,
                  letterSpacing: 2,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '>> WINNER: ${winner.player.displayName}',
                style: const TextStyle(
                  color: CyberpunkColors.green,
                  fontSize: 12,
                  letterSpacing: 1.5,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 8),
              ...playerScores.map(
                (ps) => Text(
                  '   ${ps.player.displayName.padRight(12)} ${ps.score.toString().padLeft(4)} pts',
                  style: const TextStyle(
                    color: CyberpunkColors.textSecondary,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Terminal log snippet (last 8 lines)
              const Text(
                '// SIGNAL_LOG',
                style: TextStyle(
                  color: CyberpunkColors.cyanDim,
                  fontSize: 9,
                  letterSpacing: 2,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                color: const Color(0xFF030810),
                height: 90,
                child: ListView(
                  reverse: true,
                  children: logLines.reversed
                      .take(8)
                      .map(
                        (l) => Text(
                          l,
                          style: TextStyle(
                            color: CyberpunkColors.green.withValues(alpha: 0.75),
                            fontSize: 8.5,
                            fontFamily: 'monospace',
                            height: 1.5,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),

              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: onRestart,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: CyberpunkColors.cyan, width: 1),
                          color: CyberpunkColors.cyan.withValues(alpha: 0.06),
                        ),
                        child: const Text(
                          '> RESTART.sh',
                          style: TextStyle(
                            color: CyberpunkColors.cyan,
                            fontSize: 11,
                            letterSpacing: 2,
                            fontFamily: 'monospace',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: CyberpunkColors.textDim,
                            width: 1,
                          ),
                        ),
                        child: const Text(
                          '> EXIT',
                          style: TextStyle(
                            color: CyberpunkColors.textSecondary,
                            fontSize: 11,
                            letterSpacing: 2,
                            fontFamily: 'monospace',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
