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

class _LobbyScreenState extends ConsumerState<LobbyScreen>
    with TickerProviderStateMixin {
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

  // ── Cursor blink (locked Wired section) ───────────────────────────────────
  bool _cursorVisible = true;
  late final AnimationController _cursorCtrl;

  // ── LAN host options ──────────────────────────────────────────────────────
  int _boardSize = 19;
  int _maxPlayers = 2;

  // ── Solo options ──────────────────────────────────────────────────────────
  int _soloBoardSize = 9;
  BotDifficulty _soloDifficulty = BotDifficulty.intermediate;

  @override
  void initState() {
    super.initState();
    _cursorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..addStatusListener((s) {
        if (!mounted) return;
        if (s == AnimationStatus.completed) {
          setState(() => _cursorVisible = false);
          _cursorCtrl.reverse();
        } else if (s == AnimationStatus.dismissed) {
          setState(() => _cursorVisible = true);
          _cursorCtrl.forward();
        }
      })
      ..forward();
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
    _cursorCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ʕ•ᴥ•ʔ',
                style: TextStyle(
                  color: CyberpunkColors.green,
                  fontSize: 30,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 14),
              ..._bootLines.take(_bootStep).map(
                    (line) => Text(
                      '> $line',
                      style: const TextStyle(
                        color: CyberpunkColors.green,
                        fontSize: 12,
                        fontFamily: 'monospace',
                        letterSpacing: 1.5,
                        height: 2.0,
                      ),
                    ),
                  ),
              if (_bootStep < _bootLines.length)
                const Text(
                  '> _',
                  style: TextStyle(
                    color: CyberpunkColors.green,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    height: 2.0,
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'ʕ•ᴥ•ʔ',
                    style: TextStyle(
                      color: CyberpunkColors.green,
                      fontSize: 24,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'GoHackMe',
                        style: TextStyle(
                          color: CyberpunkColors.green,
                          fontSize: 30,
                          letterSpacing: 6,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'PROTOCOL 7 :: WIRED GO',
                        style: TextStyle(
                          color: CyberpunkColors.green.withValues(alpha: 0.40),
                          fontSize: 10,
                          letterSpacing: 4,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 32),

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

              // ── THE WIRED (locked) ────────────────────────────────────
              _WiredLockedPanel(cursorVisible: _cursorVisible),

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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
        color: accentColor.withValues(alpha: 0.03),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            header,
            style: TextStyle(
              color: accentColor,
              fontSize: 11,
              letterSpacing: 2,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(
              color: CyberpunkColors.textDim,
              fontSize: 9,
              fontFamily: 'monospace',
              height: 1.7,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ── _WiredLockedPanel ─────────────────────────────────────────────────────

class _WiredLockedPanel extends StatelessWidget {
  final bool cursorVisible;
  const _WiredLockedPanel({required this.cursorVisible});

  @override
  Widget build(BuildContext context) {
    const indigo = Color(0xFF7B4FAF);
    const indigoDim = Color(0xFF3A1A5E);
    const indigoBg = Color(0xFF150828);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: indigoDim.withValues(alpha: 0.7)),
        color: indigoBg.withValues(alpha: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '// THE_WIRED',
                style: TextStyle(
                  color: indigo,
                  fontSize: 11,
                  letterSpacing: 2,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: indigo.withValues(alpha: 0.45)),
                ),
                child: const Text(
                  'UPLINK NOT ESTABLISHED',
                  style: TextStyle(
                    color: indigo,
                    fontSize: 8,
                    letterSpacing: 1.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Global network. Entities from all layers. No distance.',
            style: TextStyle(
              color: Color(0xFF4A2A6A),
              fontSize: 9,
              fontFamily: 'monospace',
              height: 1.7,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '> PROTOCOL_7 :: OFFLINE ${cursorVisible ? '_' : ' '}',
            style: const TextStyle(
              color: Color(0xFF5A3080),
              fontSize: 11,
              fontFamily: 'monospace',
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
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


