import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/cyberpunk_colors.dart';
import '../../../core/widgets/glitch_overlay.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/wired_game_provider.dart';
import '../../../services/lan_player.dart';
import '../widgets/game_layout.dart';

// ── Accent palette for The Wired ─────────────────────────────────────────

const _kIndigo = Color(0xFF8B5CF6);        // vivid indigo
const _kIndigoFaint = Color(0xFF1E0A40);   // very dim indigo for borders
const _kIndigoBg = Color(0xFF0A0614);      // near-black with indigo cast

// ── WiredGameScreen ───────────────────────────────────────────────────────

/// Multiplayer game screen for "The Wired" (WebRTC internet P2P) mode.
///
/// [isHost] determines whether this device acts as the game server.
/// Host: [boardSize] + [maxPlayers] are used to initialise the room.
/// Client: enter the host's invite code via the UI.
class WiredGameScreen extends ConsumerStatefulWidget {
  final bool isHost;
  final int boardSize;
  final int maxPlayers;

  const WiredGameScreen({
    super.key,
    required this.isHost,
    this.boardSize = 19,
    this.maxPlayers = 2,
  });

  @override
  ConsumerState<WiredGameScreen> createState() => _WiredGameScreenState();
}

class _WiredGameScreenState extends ConsumerState<WiredGameScreen> {
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    if (!widget.isHost) return; // clients start on the join screen

    final auth = ref.read(authProvider).valueOrNull;
    final playerId =
        auth?.playerId ?? 'player_${DateTime.now().millisecondsSinceEpoch}';
    final rawName = auth?.displayName ?? '';
    final displayName = rawName.isNotEmpty ? rawName.toUpperCase() : 'ANONYMOUS';

    ref.read(wiredGameProvider.notifier).openAsHost(
          playerId: playerId,
          displayName: displayName,
          boardSize: widget.boardSize,
          maxPlayers: widget.maxPlayers,
        );
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(wiredGameProvider);

    return Scaffold(
      backgroundColor: _kIndigoBg,
      body: GlitchOverlay(
        burstSignal: _attackGlitch,
        child: _buildBody(context, ws),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WiredGameState ws) {
    switch (ws.status) {
      case WiredStatus.idle:
        return widget.isHost
            ? const _BootScreen()
            : _JoinEntryScreen(
                onSubmit: _onClientJoin,
                onBack: () => _leave(context),
              );

      case WiredStatus.generatingInvite:
        return const _WiredLoadingScreen(label: 'GENERATING_HANDSHAKE...');

      case WiredStatus.connecting:
        return const _WiredLoadingScreen(label: 'CONNECTING_TO_RELAY...');

      case WiredStatus.waiting:
        // Host: lobby panel with relay code + player list
        // Client: spinner waiting for channel to open
        return ws.role == WiredRole.host
            ? _HostWaitingPanel(
                roomCode: ws.roomCode,
                inviteCode: ws.inviteCode,
                players: ws.connectedPlayers,
                maxPlayers: ws.maxPlayers,
                logLines: ws.logLines,
                onInvite: () =>
                    ref.read(wiredGameProvider.notifier).generateInviteCode(),
                onStart: ws.connectedPlayers.length >= 2
                    ? () => ref.read(wiredGameProvider.notifier).startGame()
                    : null,
                onBack: () => _leave(context),
              )
            : _ClientWaitingPanel(
                logLines: ws.logLines,
                onBack: () => _leave(context),
              );

      case WiredStatus.over:
        return _GameOverPanel(
          state: ws.gameState!,
          logLines: ws.logLines,
          onBack: () => _leave(context),
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
          onExit: () => _leave(context),
          onPass: () => ref.read(wiredGameProvider.notifier).pass(),
          onPlace: (pos) {
            setState(() => _lastPlaced = pos);
            ref.read(wiredGameProvider.notifier).placeStone(pos);
          },
          onAttack: (action) {
            _attackGlitch.value++;
            ref.read(wiredGameProvider.notifier).launchAttack(action);
          },
        );

      case WiredStatus.error:
        return _ErrorScreen(
          message: ws.errorMessage ?? 'UNKNOWN_ERROR',
          onBack: () => _leave(context),
        );
    }
  }

  Future<void> _onClientJoin(String code) async {
    final auth = ref.read(authProvider).valueOrNull;
    final playerId =
        auth?.playerId ?? 'player_${DateTime.now().millisecondsSinceEpoch}';
    final rawName = auth?.displayName ?? '';
    final displayName = rawName.isNotEmpty ? rawName.toUpperCase() : 'ANONYMOUS';

    await ref.read(wiredGameProvider.notifier).joinWithCode(
          relayCode: code.trim().toUpperCase(),
          playerId: playerId,
          displayName: displayName,
        );
  }

  void _leave(BuildContext context) {
    ref.read(wiredGameProvider.notifier).leave();
    context.go(Routes.lobby);
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
            color: _kIndigo,
            fontSize: 28,
            fontFamily: 'monospace',
          ),
        ),
      );
}

// ── _WiredLoadingScreen ────────────────────────────────────────────────────

class _WiredLoadingScreen extends StatelessWidget {
  final String label;
  const _WiredLoadingScreen({required this.label});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: _kIndigo, strokeWidth: 1.5),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: const TextStyle(
                color: _kIndigo,
                fontSize: 10,
                letterSpacing: 2,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
}

// ── _ErrorScreen ───────────────────────────────────────────────────────────

class _ErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback onBack;
  const _ErrorScreen({required this.message, required this.onBack});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'UPLINK_FAILED',
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

// ── _JoinEntryScreen ──────────────────────────────────────────────────────

/// Client-side: text field to type the host's 8-char relay code.
class _JoinEntryScreen extends StatefulWidget {
  final Future<void> Function(String code) onSubmit;
  final VoidCallback onBack;
  const _JoinEntryScreen({required this.onSubmit, required this.onBack});

  @override
  State<_JoinEntryScreen> createState() => _JoinEntryScreenState();
}

class _JoinEntryScreenState extends State<_JoinEntryScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    await widget.onSubmit(code);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '// JOIN_THE_WIRED',
              style: TextStyle(
                color: _kIndigo,
                fontSize: 18,
                letterSpacing: 3,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter the 8-character RELAY_CODE from the host.',
              style: TextStyle(
                color: CyberpunkColors.textSecondary,
                fontSize: 9,
                fontFamily: 'monospace',
                height: 1.7,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                    color: _kIndigo.withValues(alpha: 0.40), width: 1),
                color: _kIndigoBg,
              ),
              child: TextField(
                controller: _ctrl,
                style: const TextStyle(
                  color: CyberpunkColors.textPrimary,
                  fontSize: 18,
                  fontFamily: 'monospace',
                  letterSpacing: 4,
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 8,
                decoration: const InputDecoration(
                  hintText: 'ABCD1234',
                  hintStyle: TextStyle(
                    color: CyberpunkColors.textDim,
                    fontSize: 18,
                    fontFamily: 'monospace',
                    letterSpacing: 4,
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  border: InputBorder.none,
                  counterText: '',
                ),
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kIndigo.withValues(alpha: 0.15),
                  foregroundColor: _kIndigo,
                  side: const BorderSide(color: _kIndigo),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: _kIndigo, strokeWidth: 1.5),
                      )
                    : const Text('CONNECT'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: widget.onBack,
                style: OutlinedButton.styleFrom(
                  foregroundColor: CyberpunkColors.textDim,
                  side: BorderSide(
                      color: CyberpunkColors.textDim.withValues(alpha: 0.4)),
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

// ── _HostWaitingPanel ─────────────────────────────────────────────────────

class _HostWaitingPanel extends StatelessWidget {
  final String roomCode;

  /// The current relay code to share with a guest (null if not yet generated).
  final String? inviteCode;
  final List<LanPlayer> players;
  final int maxPlayers;
  final List<String> logLines;
  final VoidCallback onInvite;
  final VoidCallback? onStart;
  final VoidCallback onBack;

  const _HostWaitingPanel({
    required this.roomCode,
    required this.inviteCode,
    required this.players,
    required this.maxPlayers,
    required this.logLines,
    required this.onInvite,
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
            const Text(
              '// THE_WIRED — HOST',
              style: TextStyle(
                color: _kIndigo,
                fontSize: 16,
                letterSpacing: 3,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'ROOM:$roomCode',
              style: const TextStyle(
                color: CyberpunkColors.amber,
                fontSize: 14,
                letterSpacing: 4,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),

            // Relay code display (shown after generating an invite)
            if (inviteCode != null) _RelayCodeBox(relayCode: inviteCode!),

            const SizedBox(height: 8),

            // Player list
            Text(
              '// WIRED_NODES (${players.length}/$maxPlayers)',
              style: TextStyle(
                color: _kIndigo.withValues(alpha: 0.7),
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
                        style: TextStyle(color: _kIndigo, fontSize: 10)),
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

            if (players.length < maxPlayers) ...[  
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onInvite,
                  icon: const Icon(Icons.add_link, size: 14),
                  label: Text(
                      inviteCode == null ? 'INVITE_NODE' : 'NEW_INVITE'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kIndigo,
                    side: BorderSide(color: _kIndigo.withValues(alpha: 0.6)),
                  ),
                ),
              ),
            ],

            const Spacer(),

            // Log tail
            if (logLines.isNotEmpty)
              Container(
                height: 70,
                color: const Color(0xFF040210),
                padding: const EdgeInsets.all(6),
                child: ListView.builder(
                  reverse: true,
                  itemCount: logLines.length,
                  itemBuilder: (_, i) => Text(
                    logLines[logLines.length - 1 - i],
                    style: TextStyle(
                      color: _kIndigo.withValues(alpha: 0.7),
                      fontSize: 8,
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),

            if (onStart != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onStart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kIndigo.withValues(alpha: 0.15),
                      foregroundColor: _kIndigo,
                      side: const BorderSide(color: _kIndigo),
                    ),
                    child: const Text('JACK_INTO_THE_WIRED'),
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
                      color: CyberpunkColors.textDim.withValues(alpha: 0.4)),
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

// ── _RelayCodeBox ─────────────────────────────────────────────────────────

/// Displays the 8-char relay code with a COPY button.
class _RelayCodeBox extends StatefulWidget {
  final String relayCode;
  const _RelayCodeBox({required this.relayCode});
  @override
  State<_RelayCodeBox> createState() => _RelayCodeBoxState();
}

class _RelayCodeBoxState extends State<_RelayCodeBox> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: _kIndigo.withValues(alpha: 0.6), width: 1.5),
        color: _kIndigoFaint,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'RELAY_CODE — share with guest',
                style: TextStyle(
                  color: _kIndigo,
                  fontSize: 8,
                  letterSpacing: 2,
                  fontFamily: 'monospace',
                ),
              ),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: widget.relayCode));
                  setState(() => _copied = true);
                  Future.delayed(
                      const Duration(seconds: 2),
                      () => mounted
                          ? setState(() => _copied = false)
                          : null);
                },
                child: Text(
                  _copied ? '✓ COPIED' : 'COPY',
                  style: TextStyle(
                    color: _copied
                        ? CyberpunkColors.green
                        : _kIndigo,
                    fontSize: 8,
                    letterSpacing: 1.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.relayCode,
            style: const TextStyle(
              color: CyberpunkColors.textPrimary,
              fontSize: 28,
              fontFamily: 'monospace',
              letterSpacing: 8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                      color: _kIndigo, strokeWidth: 1.5)),
              const SizedBox(width: 8),
              Text(
                'polling relay for guest connection…',
                style: TextStyle(
                  color: _kIndigo.withValues(alpha: 0.6),
                  fontSize: 8,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── _ClientWaitingPanel ────────────────────────────────────────────────────

/// Client-side: connection sent to relay, waiting for channel to open.
class _ClientWaitingPanel extends StatelessWidget {
  final List<String> logLines;
  final VoidCallback onBack;

  const _ClientWaitingPanel({
    required this.logLines,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '// THE_WIRED — CONNECTING',
              style: TextStyle(
                color: _kIndigo,
                fontSize: 16,
                letterSpacing: 3,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      color: _kIndigo, strokeWidth: 1.5),
                ),
                const SizedBox(width: 12),
                Text(
                  'Answer sent — waiting for host to complete handshake…',
                  style: TextStyle(
                    color: _kIndigo.withValues(alpha: 0.8),
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Log tail
            if (logLines.isNotEmpty)
              Container(
                height: 90,
                color: const Color(0xFF040210),
                padding: const EdgeInsets.all(6),
                child: ListView.builder(
                  reverse: true,
                  itemCount: logLines.length,
                  itemBuilder: (_, i) => Text(
                    logLines[logLines.length - 1 - i],
                    style: TextStyle(
                      color: _kIndigo.withValues(alpha: 0.7),
                      fontSize: 8,
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(
                  foregroundColor: CyberpunkColors.textDim,
                  side: BorderSide(
                      color: CyberpunkColors.textDim.withValues(alpha: 0.4)),
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
    final colorScores = Scorer.areaScore(state.board);
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
              '// SIGNAL_TERMINATED',
              style: TextStyle(
                color: CyberpunkColors.error,
                fontSize: 20,
                letterSpacing: 4,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '> FINAL_SCORES:',
              style: TextStyle(
                color: _kIndigo.withValues(alpha: 0.8),
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
                        ? CyberpunkColors.amber
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kIndigo.withValues(alpha: 0.15),
                  foregroundColor: _kIndigo,
                  side: const BorderSide(color: _kIndigo),
                ),
                child: const Text('DISCONNECT'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
