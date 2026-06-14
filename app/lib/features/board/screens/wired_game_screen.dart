import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/cyberpunk_colors.dart';
import '../../../core/widgets/glitch_overlay.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/wired_game_provider.dart';
import '../../../services/connected_player.dart';
import '../../../services/wired_server_service.dart';
import '../widgets/game_layout.dart';

// ── Wired accent aliases ───────────────────────────────────────────────────
const _kIndigo    = CyberpunkColors.violet;
const _kIndigoDim = CyberpunkColors.violetDim;
const _kIndigoBg  = CyberpunkColors.wiredIndigoBg;

// ── WiredGameScreen ────────────────────────────────────────────────────────

/// Internet ("Wired") multiplayer screen.
///
/// [isHost] = true  → creates a new room on the server, shows lobby panel.
/// [isHost] = false → shows lobby browser + code-entry panel; joins a room.
class WiredGameScreen extends ConsumerStatefulWidget {
  final bool isHost;
  final int boardSize;
  final int maxPlayers;
  /// When non-null, the join screen will auto-join this room code immediately.
  final String? initialRoomCode;

  const WiredGameScreen({
    super.key,
    required this.isHost,
    this.boardSize = 19,
    this.maxPlayers = 2,
    this.initialRoomCode,
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
    // Ensure the server room is cleaned up whenever this screen leaves the tree,
    // including Android back-button / system-gesture navigation that bypasses
    // the in-app exit button.  Safe to call even if already left normally.
    ref.read(wiredGameProvider.notifier).leave();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.isHost) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initHost());
    } else if (widget.initialRoomCode != null &&
        widget.initialRoomCode!.isNotEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _onClientJoin(widget.initialRoomCode!));
    }
  }

  Future<void> _initHost() async {
    final auth = ref.read(authProvider).valueOrNull;
    final playerId = auth?.playerId ?? const Uuid().v4();
    final rawName = auth?.displayName ?? '';
    final displayName =
        rawName.isNotEmpty ? rawName.toUpperCase() : 'ANONYMOUS';

    await ref.read(wiredGameProvider.notifier).openAsHost(
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
        // Host: brief flash before _initHost fires.
        // Client: never reaches idle — goes straight to lobby browser.
        return widget.isHost
            ? const _Spinner(label: 'INITIALISING...')
            : _LobbyBrowserScreen(
                onJoin: _onClientJoin,
                onBack: () => _leave(context),
              );

      case WiredStatus.connecting:
        return const _Spinner(label: 'CONNECTING_TO_SERVER...');

      case WiredStatus.waking:
        return _WakingPanel(onBack: () => _leave(context));

      case WiredStatus.waiting:
        return ws.role == WiredRole.host
            ? _HostLobbyPanel(
                roomCode: ws.roomCode,
                players: ws.connectedPlayers,
                maxPlayers: ws.maxPlayers,
                logLines: ws.logLines,
                canStart: ws.connectedPlayers.length >= 2,
                onStart: () =>
                    ref.read(wiredGameProvider.notifier).startGame(),
                onBack: () => _leave(context),
              )
            : _GuestWaitingPanel(
                roomCode: ws.roomCode,
                players: ws.connectedPlayers,
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
          serverTurnStartedAt: ws.serverTurnStartedAt,
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
          onChatSend: (text) =>
              ref.read(wiredGameProvider.notifier).sendChatMessage(text),
        );

      case WiredStatus.over:
        return _GameOverPanel(
          state: ws.gameState!,
          logLines: ws.logLines,
          onBack: () => _leave(context),
        );

      case WiredStatus.error:
        return _ErrorPanel(
          message: _friendlyError(ws.errorMessage),
          onBack: () => _leave(context),
        );
    }
  }

  Future<void> _onClientJoin(String code) async {
    final auth = ref.read(authProvider).valueOrNull;
    final playerId = auth?.playerId ?? const Uuid().v4();
    final rawName = auth?.displayName ?? '';
    final displayName =
        rawName.isNotEmpty ? rawName.toUpperCase() : 'ANONYMOUS';

    await ref.read(wiredGameProvider.notifier).joinWithCode(
          roomCode: code.trim().toUpperCase(),
          playerId: playerId,
          displayName: displayName,
        );
  }

  void _leave(BuildContext context) {
    ref.read(wiredGameProvider.notifier).leave();
    context.go(Routes.lobby);
  }
}

// ── _LobbyBrowserScreen ────────────────────────────────────────────────────

/// Guest join screen: live-refreshing room list + manual code entry.
class _LobbyBrowserScreen extends StatefulWidget {
  final Future<void> Function(String code) onJoin;
  final VoidCallback onBack;
  const _LobbyBrowserScreen({required this.onJoin, required this.onBack});

  @override
  State<_LobbyBrowserScreen> createState() => _LobbyBrowserScreenState();
}

class _LobbyBrowserScreenState extends State<_LobbyBrowserScreen> {
  final _codeCtrl = TextEditingController();
  List<WiredRoomInfo> _rooms = [];
  bool _loading = true;
  bool _joining = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final rooms = await WiredServerService.fetchOpenRooms();
    if (mounted) setState(() { _rooms = rooms; _loading = false; });
  }

  Future<void> _join(String code) async {
    if (code.isEmpty) return;
    setState(() { _joining = true; });
    await widget.onJoin(code);
    if (mounted) setState(() => _joining = false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_ios_new, size: 14),
                  color: Colors.white,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                const Text(
                  '// THE_WIRED — OPEN_CHANNELS',
                  style: TextStyle(
                    color: _kIndigo,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        color: _kIndigoDim, strokeWidth: 1.5),
                  )
                else
                  GestureDetector(
                    onTap: () { setState(() => _loading = true); _refresh(); },
                    child: const Icon(Icons.refresh,
                        size: 16, color: _kIndigoDim),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              AppConfig.isWiredConfigured
                  ? 'SCANNING WIRED CHANNELS...'
                  : 'NO_SERVER_URL — run with --dart-define=WIRED_SERVER_URL=...',
              style: TextStyle(
                color: AppConfig.isWiredConfigured
                    ? CyberpunkColors.textDim
                    : CyberpunkColors.error,
                fontSize: 8,
                fontFamily: 'monospace',
                letterSpacing: 1.2,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Container(height: 1,
                color: _kIndigo.withValues(alpha: 0.18)),
          ),

          // ── Room list ──────────────────────────────────────────────────
          Expanded(
            child: _rooms.isEmpty && !_loading
                ? Center(
                    child: Text(
                      'NO_OPEN_CHANNELS_FOUND\nBe the first to host.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: CyberpunkColors.textDim,
                        fontSize: 10,
                        fontFamily: 'monospace',
                        height: 1.9,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 4),
                    itemCount: _rooms.length,
                    separatorBuilder: (_, __) => Container(
                      height: 1,
                      color: _kIndigo.withValues(alpha: 0.10),
                    ),
                    itemBuilder: (_, i) => _RoomRow(
                      room: _rooms[i],
                      onJoin: _joining ? null : () => _join(_rooms[i].code),
                    ),
                  ),
          ),

          // ── Manual code entry ──────────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: _kIndigo.withValues(alpha: 0.28)),
              color: _kIndigoBg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MANUAL UPLINK — enter ROOM_CODE',
                  style: TextStyle(
                    color: _kIndigoDim,
                    fontSize: 8,
                    fontFamily: 'monospace',
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeCtrl,
                        style: const TextStyle(
                          color: CyberpunkColors.textPrimary,
                          fontSize: 18,
                          fontFamily: 'monospace',
                          letterSpacing: 4,
                        ),
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 8,
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'ABCD12',
                          hintStyle: TextStyle(
                            color: CyberpunkColors.textDim,
                            fontSize: 18,
                            fontFamily: 'monospace',
                            letterSpacing: 4,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _joining
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: _kIndigo, strokeWidth: 1.5),
                          )
                        : TextButton(
                            onPressed: () =>
                                _join(_codeCtrl.text.trim().toUpperCase()),
                            style: TextButton.styleFrom(
                              foregroundColor: _kIndigoBg,
                              backgroundColor: _kIndigo,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                            ),
                            child: const Text(
                              'CONNECT',
                              style: TextStyle(
                                  fontSize: 10, fontFamily: 'monospace'),
                            ),
                          ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── _RoomRow ───────────────────────────────────────────────────────────────

class _RoomRow extends StatelessWidget {
  final WiredRoomInfo room;
  final VoidCallback? onJoin;
  const _RoomRow({required this.room, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final full = room.playerCount >= room.maxPlayers;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          // Code
          Text(
            room.code,
            style: const TextStyle(
              color: CyberpunkColors.textPrimary,
              fontSize: 14,
              fontFamily: 'monospace',
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 16),
          // Board size tag
          _Tag('${room.boardSize}×${room.boardSize}', CyberpunkColors.cyanDim),
          const SizedBox(width: 8),
          if (room.reconnecting) ...[
            _Tag('IN_PROGRESS', CyberpunkColors.warning),
            const SizedBox(width: 6),
          ] else ...[
            // Player pips
            Row(
              children: List.generate(room.maxPlayers, (i) => Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < room.playerCount
                        ? _kIndigo
                        : _kIndigo.withValues(alpha: 0.22),
                  ),
                ),
              )),
            ),
            const SizedBox(width: 6),
            Text(
              '${room.playerCount}/${room.maxPlayers}',
              style: TextStyle(
                color: full ? CyberpunkColors.error : CyberpunkColors.textSecondary,
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
          ],
          const Spacer(),
          if (room.reconnecting)
            TextButton(
              onPressed: onJoin,
              style: TextButton.styleFrom(
                foregroundColor: _kIndigoBg,
                backgroundColor: onJoin != null
                    ? CyberpunkColors.warning
                    : CyberpunkColors.warning.withValues(alpha: 0.4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('RECONNECT',
                  style: TextStyle(fontSize: 9, fontFamily: 'monospace')),
            )
          else if (!full)
            TextButton(
              onPressed: onJoin,
              style: TextButton.styleFrom(
                foregroundColor: _kIndigoBg,
                backgroundColor: onJoin != null ? _kIndigo : _kIndigoDim,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('JOIN',
                  style: TextStyle(fontSize: 9, fontFamily: 'monospace')),
            )
          else
            _Tag('FULL', CyberpunkColors.error),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          text,
          style: TextStyle(
              color: color,
              fontSize: 8,
              fontFamily: 'monospace',
              letterSpacing: 1),
        ),
      );
}

// ── _HostLobbyPanel ────────────────────────────────────────────────────────

class _HostLobbyPanel extends StatelessWidget {
  final String roomCode;
  final List<ConnectedPlayer> players;
  final int maxPlayers;
  final List<String> logLines;
  final bool canStart;
  final VoidCallback onStart;
  final VoidCallback onBack;

  const _HostLobbyPanel({
    required this.roomCode,
    required this.players,
    required this.maxPlayers,
    required this.logLines,
    required this.canStart,
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
            // Back
            GestureDetector(
              onTap: onBack,
              child: Row(children: [
                const Icon(Icons.arrow_back_ios_new,
                    size: 12, color: Colors.white),
                const SizedBox(width: 6),
                Text('BACK',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontFamily: 'monospace')),
              ]),
            ),
            const SizedBox(height: 24),
            const Text(
              '// HOST_LOBBY',
              style: TextStyle(
                  color: _kIndigo,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  fontFamily: 'monospace'),
            ),
            const SizedBox(height: 20),
            // Room code — big and copy-friendly
            const Text('ROOM_CODE',
                style: TextStyle(
                    color: CyberpunkColors.textDim,
                    fontSize: 8,
                    letterSpacing: 2,
                    fontFamily: 'monospace')),
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                  border: Border.all(
                      color: _kIndigo.withValues(alpha: 0.55), width: 1.5)),
              child: Text(
                roomCode,
                style: const TextStyle(
                  color: CyberpunkColors.textPrimary,
                  fontSize: 32,
                  fontFamily: 'monospace',
                  letterSpacing: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Share this code with other players.',
              style: TextStyle(
                  color: CyberpunkColors.textDim,
                  fontSize: 8,
                  fontFamily: 'monospace'),
            ),
            const SizedBox(height: 24),
            // Player list
            Text(
              'PLAYERS  ${players.length}/$maxPlayers',
              style: const TextStyle(
                  color: CyberpunkColors.textSecondary,
                  fontSize: 9,
                  letterSpacing: 2,
                  fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            ...players.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: _kIndigo, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(p.displayName,
                      style: const TextStyle(
                          color: CyberpunkColors.textPrimary,
                          fontSize: 11,
                          fontFamily: 'monospace')),
                ]),
              ),
            ),
            const Spacer(),
            // Log
            if (logLines.isNotEmpty)
              SizedBox(
                height: 60,
                child: ListView(
                  children: logLines
                      .reversed
                      .take(6)
                      .map((l) => Text(l,
                          style: TextStyle(
                              color: CyberpunkColors.textDim,
                              fontSize: 8,
                              fontFamily: 'monospace')))
                      .toList(),
                ),
              ),
            const SizedBox(height: 16),
            // Start button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canStart ? onStart : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canStart ? _kIndigo : _kIndigoDim,
                  foregroundColor: _kIndigoBg,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const RoundedRectangleBorder(),
                ),
                child: Text(
                  canStart
                      ? 'START_GAME  [${players.length}/$maxPlayers]'
                      : 'WAITING_FOR_PLAYERS...',
                  style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      letterSpacing: 2),
                ),
              ),
            ),
            if (!canStart) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onBack,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CyberpunkColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder(),
                  ),
                  child: const Text(
                    '[ABORT]',
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        letterSpacing: 2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── _GuestWaitingPanel ─────────────────────────────────────────────────────

class _GuestWaitingPanel extends StatelessWidget {
  final String roomCode;
  final List<ConnectedPlayer> players;
  final List<String> logLines;
  final VoidCallback onBack;

  const _GuestWaitingPanel({
    required this.roomCode,
    required this.players,
    required this.logLines,
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
            GestureDetector(
              onTap: onBack,
              child: Row(children: [
                const Icon(Icons.arrow_back_ios_new,
                    size: 12, color: Colors.white),
                const SizedBox(width: 6),
                Text('BACK',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontFamily: 'monospace')),
              ]),
            ),
            const SizedBox(height: 24),
            const Text(
              '// UPLINK_ESTABLISHED',
              style: TextStyle(
                  color: _kIndigo,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  fontFamily: 'monospace'),
            ),
            const SizedBox(height: 6),
            Text('ROOM: $roomCode',
                style: const TextStyle(
                    color: CyberpunkColors.textSecondary,
                    fontSize: 10,
                    letterSpacing: 2,
                    fontFamily: 'monospace')),
            const SizedBox(height: 24),
            const Row(children: [
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      color: _kIndigo, strokeWidth: 1.5)),
              SizedBox(width: 10),
              Text(
                'Waiting for host to start...',
                style: TextStyle(
                    color: CyberpunkColors.textSecondary,
                    fontSize: 10,
                    fontFamily: 'monospace'),
              ),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onBack,
                style: ElevatedButton.styleFrom(
                  backgroundColor: CyberpunkColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const RoundedRectangleBorder(),
                ),
                child: const Text(
                  '[ABORT]',
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      letterSpacing: 2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (players.isNotEmpty) ...[
              Text('PLAYERS',
                  style: TextStyle(
                      color: CyberpunkColors.textDim,
                      fontSize: 8,
                      letterSpacing: 2,
                      fontFamily: 'monospace')),
              const SizedBox(height: 8),
              ...players.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                              color: _kIndigo, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(p.displayName,
                          style: const TextStyle(
                              color: CyberpunkColors.textPrimary,
                              fontSize: 11,
                              fontFamily: 'monospace')),
                    ]),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

// ── _Spinner ───────────────────────────────────────────────────────────────

// ── _WakingPanel ───────────────────────────────────────────────────────────

/// Shown when the Render.com server is in sleep mode and the service is
/// automatically retrying.  Displays an animated status and a cancel button.
class _WakingPanel extends StatefulWidget {
  final VoidCallback onBack;
  const _WakingPanel({required this.onBack});

  @override
  State<_WakingPanel> createState() => _WakingPanelState();
}

class _WakingPanelState extends State<_WakingPanel> {
  int _dots = 0;
  Timer? _anim;

  @override
  void initState() {
    super.initState();
    _anim = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (mounted) setState(() => _dots = (_dots + 1) % 4);
    });
  }

  @override
  void dispose() {
    _anim?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: _kIndigo, strokeWidth: 1.5),
              ),
              const SizedBox(height: 22),
              Text(
                'WAKING_UP_SERVER${'.' * _dots}',
                style: const TextStyle(
                  color: _kIndigo,
                  fontSize: 13,
                  letterSpacing: 2,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'The server is spinning up from sleep mode.\nRetrying automatically — this takes ~30 s.',
                style: TextStyle(
                  color: CyberpunkColors.textSecondary,
                  fontSize: 9,
                  fontFamily: 'monospace',
                  height: 1.8,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              TextButton(
                onPressed: widget.onBack,
                child: const Text(
                  '< CANCEL',
                  style: TextStyle(
                    color: _kIndigoDim,
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

// ── _Spinner ───────────────────────────────────────────────────────────────

class _Spinner extends StatelessWidget {
  final String label;
  const _Spinner({required this.label});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: _kIndigo, strokeWidth: 1.5)),
            const SizedBox(height: 16),
            Text(label,
                style: const TextStyle(
                    color: _kIndigo,
                    fontSize: 10,
                    letterSpacing: 2,
                    fontFamily: 'monospace')),
          ],
        ),
      );
}

// ── Error code → human-readable message ──────────────────────────────────

String _friendlyError(String? code) => switch (code) {
      'SERVER_FULL'          => 'Server is at capacity — please try again later',
      'ROOM_FULL'            => 'This room is already full',
      'GAME_ALREADY_STARTED' => 'This game has already started',
      'ROOM_NOT_FOUND'       => 'Room code not found',
      'ALREADY_IN_ROOM'      => 'You are already in this room',
      _                      => code ?? 'UPLINK_FAILED',
    };

// ── _ErrorPanel ────────────────────────────────────────────────────────────

class _ErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback onBack;
  const _ErrorPanel({required this.message, required this.onBack});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('UPLINK_FAILED',
                  style: TextStyle(
                      color: CyberpunkColors.error,
                      fontSize: 16,
                      letterSpacing: 3,
                      fontFamily: 'monospace')),
              const SizedBox(height: 12),
              Text(message,
                  style: const TextStyle(
                      color: CyberpunkColors.textSecondary,
                      fontSize: 10,
                      fontFamily: 'monospace'),
                  textAlign: TextAlign.center),
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

// ── _GameOverPanel ─────────────────────────────────────────────────────────

class _GameOverPanel extends StatelessWidget {
  final GameState state;
  final List<String> logLines;
  final VoidCallback onBack;
  const _GameOverPanel(
      {required this.state, required this.logLines, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final scores = state.players.map((p) {
      final count = state.captureCount[p.id] ?? 0;
      return '${p.displayName}: $count captures';
    }).toList();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('GAME_OVER',
                style: TextStyle(
                    color: _kIndigo,
                    fontSize: 20,
                    letterSpacing: 4,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            ...scores.map((s) => Text(s,
                style: const TextStyle(
                    color: CyberpunkColors.textPrimary,
                    fontSize: 11,
                    fontFamily: 'monospace'))),
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
