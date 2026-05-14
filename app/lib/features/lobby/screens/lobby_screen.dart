import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/cyberpunk_colors.dart';

/// Main lobby screen — three connection modes presented as NAVI protocols.
///
///   • CLOSED CIRCUIT — 1v1 against the local entity (no network)
///   • LOCAL WIRED    — LAN multiplayer; one device opens a LAYER
///   • THE WIRED      — Global internet mode (uplink not yet established)
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  // ── Boot sequence ─────────────────────────────────────────────────────────
  static const _bootLines = [
    'NAVI :: SYSTEM BOOT v7.1',
    'SCANNING LOCAL WIRED...',
    'ENTITY IDENTIFIED.',
    'PROTOCOL STACK LOADED.',
    'READY.',
  ];
  int _bootStep = 0;
  bool _booted = false;

  // ── LAN host options ──────────────────────────────────────────────────────
  int _boardSize = 19;
  int _maxPlayers = 2;

  // ── Wired options ─────────────────────────────────────────────────────────
  int _wiredBoardSize = 19;
  int _wiredMaxPlayers = 2;

  // ── Solo options ──────────────────────────────────────────────────────────
  int _soloBoardSize = 9;
  BotDifficulty _soloDifficulty = BotDifficulty.intermediate;

  @override
  void initState() {
    super.initState();
    _runBoot();
  }

  void _runBoot() {
    for (int i = 0; i < _bootLines.length; i++) {
      Future.delayed(Duration(milliseconds: 280 + i * 420), () {
        if (!mounted) return;
        setState(() => _bootStep = i + 1);
        if (i == _bootLines.length - 1) {
          Future.delayed(const Duration(milliseconds: 480), () {
            if (mounted) setState(() => _booted = true);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _openNavi() => context.push(Routes.navi);

  void _hostLan() => context.push(
        Routes.lanHost,
        extra: {'boardSize': _boardSize, 'maxPlayers': _maxPlayers},
      );

  void _joinLan() => context.push(Routes.lanJoin);

  void _launchSolo() => context.push(
        Routes.solo,
        extra: {
          'boardSize': _soloBoardSize,
          'difficulty': _soloDifficulty == BotDifficulty.beginner
              ? 'beginner'
              : 'intermediate',
        },
      );

  void _hostWired() => context.push(
        Routes.wiredHost,
        extra: {'boardSize': _wiredBoardSize, 'maxPlayers': _wiredMaxPlayers},
      );

  void _joinWired() => context.push(Routes.wiredJoin);

  // ── Segmented button style ────────────────────────────────────────────────

  ButtonStyle _segStyle(Color accent) => ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? CyberpunkColors.background
              : accent.withValues(alpha: 0.55),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? accent
              : Colors.transparent,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return _booted ? _buildMain() : _buildBoot();
  }

  // ── Boot screen ────────────────────────────────────────────────────────────

  Widget _buildBoot() {
    return Scaffold(
      backgroundColor: CyberpunkColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(36, 48, 36, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GOHACKME:NET',
                style: TextStyle(
                  color: CyberpunkColors.green.withValues(alpha: 0.55),
                  fontSize: 9,
                  letterSpacing: 3,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 4),
              Container(
                height: 1,
                color: CyberpunkColors.cyanDim.withValues(alpha: 0.18),
              ),
              const SizedBox(height: 28),
              ..._bootLines.take(_bootStep).map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        line,
                        style: TextStyle(
                          color: CyberpunkColors.green.withValues(alpha: 0.55),
                          fontSize: 9.5,
                          fontFamily: 'monospace',
                          letterSpacing: 1.3,
                          height: 1.7,
                        ),
                      ),
                    ),
                  ),
              if (_bootStep < _bootLines.length)
                Text(
                  '▌',
                  style: TextStyle(
                    color: CyberpunkColors.green.withValues(alpha: 0.45),
                    fontSize: 9.5,
                    fontFamily: 'monospace',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Main menu ─────────────────────────────────────────────────────────────

  Widget _buildMain() {
    return Scaffold(
      backgroundColor: CyberpunkColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 36),

              // ── Title ─────────────────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GoHackMe',
                    style: TextStyle(
                      color: CyberpunkColors.green.withValues(alpha: 0.95),
                      fontSize: 26,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PROTOCOL_7  ·  WIRED GO NETWORK',
                    style: TextStyle(
                      color: CyberpunkColors.cyanDim.withValues(alpha: 0.80),
                      fontSize: 9,
                      letterSpacing: 3,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── NAVI button ───────────────────────────────────────────
              _NaviButton(onTap: _openNavi),

              const SizedBox(height: 28),

              // ── LOCAL WIRED ───────────────────────────────────────────
              _LainPanel(
                accentColor: CyberpunkColors.green,
                header: '// LOCAL_WIRED.protocol',
                description:
                    'All entities must share the same local network.\n'
                    'Open a LAYER — others connect automatically.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionLabel('NETWORK_SCALE',
                        color: CyberpunkColors.green),
                    const SizedBox(height: 6),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 9, label: Text('9×9')),
                        ButtonSegment(value: 13, label: Text('13×13')),
                        ButtonSegment(value: 19, label: Text('19×19')),
                      ],
                      selected: {_boardSize},
                      onSelectionChanged: (s) =>
                          setState(() => _boardSize = s.first),
                      style: _segStyle(CyberpunkColors.green),
                    ),
                    const SizedBox(height: 14),
                    _SectionLabel('ENTITIES', color: CyberpunkColors.green),
                    const SizedBox(height: 6),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 2, label: Text('2')),
                        ButtonSegment(value: 3, label: Text('3')),
                        ButtonSegment(value: 4, label: Text('4')),
                      ],
                      selected: {_maxPlayers},
                      onSelectionChanged: (s) =>
                          setState(() => _maxPlayers = s.first),
                      style: _segStyle(CyberpunkColors.green),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _hostLan,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  CyberpunkColors.green.withValues(alpha: 0.12),
                              foregroundColor: CyberpunkColors.green,
                              side:
                                  const BorderSide(color: CyberpunkColors.green),
                            ),
                            child: const Text('OPEN_LAYER'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _joinLan,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  CyberpunkColors.cyan.withValues(alpha: 0.10),
                              foregroundColor: CyberpunkColors.cyan,
                              side:
                                  const BorderSide(color: CyberpunkColors.cyan),
                            ),
                            child: const Text('CONNECT_TO_LAYER'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── CLOSED CIRCUIT ────────────────────────────────────────
              _LainPanel(
                accentColor: CyberpunkColors.magenta,
                header: '// CLOSED_CIRCUIT.exe',
                description: 'Isolated session. 1v1 against the local entity.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionLabel('NETWORK_SCALE',
                        color: CyberpunkColors.magenta),
                    const SizedBox(height: 6),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 9, label: Text('9×9')),
                        ButtonSegment(value: 13, label: Text('13×13')),
                        ButtonSegment(value: 19, label: Text('19×19')),
                      ],
                      selected: {_soloBoardSize},
                      onSelectionChanged: (s) =>
                          setState(() => _soloBoardSize = s.first),
                      style: _segStyle(CyberpunkColors.magenta),
                    ),
                    const SizedBox(height: 14),
                    _SectionLabel('ENTITY_LEVEL',
                        color: CyberpunkColors.magenta),
                    const SizedBox(height: 6),
                    SegmentedButton<BotDifficulty>(
                      segments: const [
                        ButtonSegment(
                          value: BotDifficulty.beginner,
                          label: Text('LAYER_1'),
                        ),
                        ButtonSegment(
                          value: BotDifficulty.intermediate,
                          label: Text('LAYER_2'),
                        ),
                      ],
                      selected: {_soloDifficulty},
                      onSelectionChanged: (s) =>
                          setState(() => _soloDifficulty = s.first),
                      style: _segStyle(CyberpunkColors.magenta),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _launchSolo,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              CyberpunkColors.magenta.withValues(alpha: 0.12),
                          foregroundColor: CyberpunkColors.magenta,
                          side: const BorderSide(
                            color: CyberpunkColors.magenta,
                          ),
                        ),
                        child: const Text('JACK_IN'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── THE WIRED (internet P2P) ─────────────────────────────────────────
              _WiredPanel(
                boardSize: _wiredBoardSize,
                maxPlayers: _wiredMaxPlayers,
                segStyle: _segStyle,
                onBoardSize: (v) => setState(() => _wiredBoardSize = v),
                onMaxPlayers: (v) => setState(() => _wiredMaxPlayers = v),
                onHost: _hostWired,
                onJoin: _joinWired,
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _LainPanel ─────────────────────────────────────────────────────────────

class _LainPanel extends StatelessWidget {
  final Color accentColor;
  final String header;
  final String description;
  final Widget child;

  const _LainPanel({
    required this.accentColor,
    required this.header,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: accentColor.withValues(alpha: 0.55), width: 2),
          bottom: BorderSide(color: accentColor.withValues(alpha: 0.12), width: 1),
        ),
        color: accentColor.withValues(alpha: 0.025),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            header,
            style: TextStyle(
              color: accentColor.withValues(alpha: 0.95),
              fontSize: 10,
              letterSpacing: 2.5,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              color: CyberpunkColors.textSecondary.withValues(alpha: 0.85),
              fontSize: 9,
              fontFamily: 'monospace',
              height: 1.8,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ── _WiredPanel ───────────────────────────────────────────────────────────

class _WiredPanel extends StatelessWidget {
  final int boardSize;
  final int maxPlayers;
  final ButtonStyle Function(Color) segStyle;
  final ValueChanged<int> onBoardSize;
  final ValueChanged<int> onMaxPlayers;
  final VoidCallback onHost;
  final VoidCallback onJoin;

  const _WiredPanel({
    required this.boardSize,
    required this.maxPlayers,
    required this.segStyle,
    required this.onBoardSize,
    required this.onMaxPlayers,
    required this.onHost,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    const indigo = Color(0xFF8B5CF6);
    const indigoDim = Color(0xFF4C1D95);
    const indigoBg = Color(0xFF0A0614);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: indigo.withValues(alpha: 0.55), width: 2),
          bottom: BorderSide(color: indigoDim.withValues(alpha: 0.20), width: 1),
        ),
        color: indigoBg.withValues(alpha: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '// THE_WIRED',
                style: TextStyle(
                  color: indigo.withValues(alpha: 0.95),
                  fontSize: 10,
                  letterSpacing: 2.5,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  border:
                      Border.all(color: indigo.withValues(alpha: 0.45)),
                ),
                child: Text(
                  'UPLINK ACTIVE',
                  style: TextStyle(
                    color: indigo.withValues(alpha: 0.80),
                    fontSize: 7.5,
                    letterSpacing: 1.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Global network. P2P via WebRTC — no server required.\n'
            'Open a LAYER and share the handshake code with your opponent.',
            style: TextStyle(
              color: CyberpunkColors.textSecondary.withValues(alpha: 0.85),
              fontSize: 9,
              fontFamily: 'monospace',
              height: 1.8,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 14),
          _SectionLabel('NETWORK_SCALE', color: indigo),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 9, label: Text('9×9')),
              ButtonSegment(value: 13, label: Text('13×13')),
              ButtonSegment(value: 19, label: Text('19×19')),
            ],
            selected: {boardSize},
            onSelectionChanged: (s) => onBoardSize(s.first),
            style: segStyle(indigo),
          ),
          const SizedBox(height: 14),
          _SectionLabel('ENTITIES', color: indigo),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
              ButtonSegment(value: 4, label: Text('4')),
            ],
            selected: {maxPlayers},
            onSelectionChanged: (s) => onMaxPlayers(s.first),
            style: segStyle(indigo),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onHost,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: indigo.withValues(alpha: 0.12),
                    foregroundColor: indigo,
                    side: BorderSide(color: indigo),
                  ),
                  child: const Text('OPEN_LAYER'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onJoin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        indigoDim.withValues(alpha: 0.20),
                    foregroundColor: indigo,
                    side: BorderSide(
                        color: indigo.withValues(alpha: 0.55)),
                  ),
                  child: const Text('JACK_IN'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── _NaviButton ───────────────────────────────────────────────────────────

class _NaviButton extends StatefulWidget {
  final VoidCallback onTap;
  const _NaviButton({required this.onTap});

  @override
  State<_NaviButton> createState() => _NaviButtonState();
}

class _NaviButtonState extends State<_NaviButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const amber = CyberpunkColors.amber;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) {
        final glow = _hovered ? 0.30 : 0.08 + _pulse.value * 0.08;
        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: amber.withValues(alpha: glow),
                border: Border.all(
                  color: amber.withValues(alpha: _hovered ? 0.65 : 0.35),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '◈',
                    style: TextStyle(
                      color: amber.withValues(alpha: 0.80),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TALK WITH YOUR NAVI',
                          style: TextStyle(
                            color: amber.withValues(alpha: 0.90),
                            fontSize: 10,
                            letterSpacing: 2.5,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ask questions · learn the rules · understand the Wired',
                          style: TextStyle(
                            color: amber.withValues(alpha: 0.45),
                            fontSize: 8.5,
                            letterSpacing: 0.8,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '[>_]',
                    style: TextStyle(
                      color: amber.withValues(alpha: _hovered ? 0.75 : 0.35),
                      fontSize: 10,
                      letterSpacing: 1,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── _SectionLabel ─────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionLabel(this.label, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: color.withValues(alpha: 0.55),
        fontSize: 10,
        letterSpacing: 2,
        fontFamily: 'monospace',
      ),
    );
  }
}


