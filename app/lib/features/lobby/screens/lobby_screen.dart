import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/cyberpunk_colors.dart';

/// Main lobby — four ASCII terminal entries; each one opens a focused
/// setup dialog before navigating.
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

  // ── Mode pickers ──────────────────────────────────────────────────────────

  void _openNavi() => context.push(Routes.navi);

  void _pickSolo() {
    _showSetupDialog(_SoloSetupDialog(
      onConfirm: (size, difficulty) {
        Navigator.of(context, rootNavigator: true).pop();
        context.push(Routes.solo, extra: {
          'boardSize': size,
          'difficulty': difficulty == BotDifficulty.beginner
              ? 'beginner'
              : 'intermediate',
        });
      },
    ));
  }

  void _pickLan() {
    _showSetupDialog(_LanSetupDialog(
      onHost: (size, players) {
        Navigator.of(context, rootNavigator: true).pop();
        context.push(Routes.lanHost,
            extra: {'boardSize': size, 'maxPlayers': players});
      },
      onJoin: () {
        Navigator.of(context, rootNavigator: true).pop();
        context.push(Routes.lanJoin);
      },
    ));
  }

  void _pickWired() {
    _showSetupDialog(_WiredSetupDialog(
      onHost: (size, players) {
        Navigator.of(context, rootNavigator: true).pop();
        context.push(Routes.wiredHost,
            extra: {'boardSize': size, 'maxPlayers': players});
      },
      onJoin: () {
        Navigator.of(context, rootNavigator: true).pop();
        context.push(Routes.wiredJoin);
      },
    ));
  }

  void _showSetupDialog(Widget dialog) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 160),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1.0).animate(anim),
          child: child,
        ),
      ),
      pageBuilder: (ctx, _, __) => dialog,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _booted ? _buildMain() : _buildBoot();
  }

  // ── Boot screen ───────────────────────────────────────────────────────────

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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title ────────────────────────────────────────────
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
              const SizedBox(height: 6),
              Container(height: 1, color: CyberpunkColors.cyanDim.withValues(alpha: 0.12)),
              const SizedBox(height: 32),

              // ── 4 terminal entries ───────────────────────────────
              _TerminalEntry(
                index: '01',
                command: 'Ntalk_to_your_navi',
                description: 'ask questions  ·  learn the Wired',
                accent: CyberpunkColors.amber,
                onTap: _openNavi,
              ),
              const SizedBox(height: 10),
              _TerminalEntry(
                index: '02',
                command: 'CLOSED_CIRCUIT',
                description: 'solo session  ·  1v1 against the machine',
                accent: CyberpunkColors.magenta,
                onTap: _pickSolo,
              ),
              const SizedBox(height: 10),
              _TerminalEntry(
                index: '03',
                command: 'LOCAL_WIRED',
                description: 'LAN multiplayer  ·  same network required',
                accent: CyberpunkColors.green,
                onTap: _pickLan,
              ),
              const SizedBox(height: 10),
              _TerminalEntry(
                index: '04',
                command: 'THE_WIRED',
                description: 'global network  ·  connect to the Wired',
                accent: const Color(0xFF8B5CF6),
                onTap: _pickWired,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _TerminalEntry ────────────────────────────────────────────────────────

class _TerminalEntry extends StatefulWidget {
  final String index;
  final String command;
  final String description;
  final Color accent;
  final VoidCallback onTap;

  const _TerminalEntry({
    required this.index,
    required this.command,
    required this.description,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_TerminalEntry> createState() => _TerminalEntryState();
}

class _TerminalEntryState extends State<_TerminalEntry> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.accent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: _hovered ? a.withValues(alpha: 0.07) : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: a.withValues(alpha: _hovered ? 0.85 : 0.40),
                width: 2,
              ),
              bottom: BorderSide(
                color: a.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                '[${widget.index}]',
                style: TextStyle(
                  color: a.withValues(alpha: 0.45),
                  fontSize: 9,
                  letterSpacing: 1,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '// ${widget.command}',
                      style: TextStyle(
                        color: a.withValues(alpha: _hovered ? 1.0 : 0.85),
                        fontSize: 11,
                        letterSpacing: 2,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.description,
                      style: TextStyle(
                        color: CyberpunkColors.textSecondary.withValues(alpha: 0.65),
                        fontSize: 8.5,
                        letterSpacing: 0.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _hovered ? '[ENTER]' : '[>_]',
                style: TextStyle(
                  color: a.withValues(alpha: _hovered ? 0.85 : 0.30),
                  fontSize: 9,
                  letterSpacing: 1,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _SetupDialog base helpers ─────────────────────────────────────────────

class _DialogShell extends StatelessWidget {
  final String title;
  final Color accent;
  final Widget body;

  const _DialogShell({
    required this.title,
    required this.accent,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF030A11),
                border: Border.all(color: accent.withValues(alpha: 0.55), width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: accent.withValues(alpha: 0.30), width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: accent.withValues(alpha: 0.90),
                            fontSize: 10,
                            letterSpacing: 2.5,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text(
                              '[X]',
                              style: TextStyle(
                                color: CyberpunkColors.textDim.withValues(alpha: 0.55),
                                fontSize: 10,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: body,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _dialogLabel(String text, Color accent) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          color: accent.withValues(alpha: 0.55),
          fontSize: 9,
          letterSpacing: 2,
          fontFamily: 'monospace',
        ),
      ),
    );

ButtonStyle _dialogSegStyle(Color accent) => ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? const Color(0xFF030A11)
            : accent.withValues(alpha: 0.55),
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? accent : Colors.transparent,
      ),
      side: WidgetStateProperty.all(
        BorderSide(color: accent.withValues(alpha: 0.40)),
      ),
    );

Widget _dialogButton(String label, Color accent, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          border: Border.all(color: accent.withValues(alpha: 0.60)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: accent.withValues(alpha: 0.95),
            fontSize: 10,
            letterSpacing: 2,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

// ── Solo setup dialog ─────────────────────────────────────────────────────

class _SoloSetupDialog extends StatefulWidget {
  final void Function(int boardSize, BotDifficulty difficulty) onConfirm;
  const _SoloSetupDialog({required this.onConfirm});

  @override
  State<_SoloSetupDialog> createState() => _SoloSetupDialogState();
}

class _SoloSetupDialogState extends State<_SoloSetupDialog> {
  int _boardSize = 9;
  BotDifficulty _difficulty = BotDifficulty.intermediate;

  static const _accent = CyberpunkColors.magenta;

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      title: '// CLOSED_CIRCUIT.exe',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dialogLabel('NETWORK_SCALE', _accent),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 9, label: Text('9×9')),
              ButtonSegment(value: 13, label: Text('13×13')),
              ButtonSegment(value: 19, label: Text('19×19')),
            ],
            selected: {_boardSize},
            onSelectionChanged: (s) => setState(() => _boardSize = s.first),
            style: _dialogSegStyle(_accent),
          ),
          const SizedBox(height: 14),
          _dialogLabel('ENTITY_LEVEL', _accent),
          SegmentedButton<BotDifficulty>(
            segments: const [
              ButtonSegment(value: BotDifficulty.beginner, label: Text('LAYER_1')),
              ButtonSegment(value: BotDifficulty.intermediate, label: Text('LAYER_2')),
            ],
            selected: {_difficulty},
            onSelectionChanged: (s) => setState(() => _difficulty = s.first),
            style: _dialogSegStyle(_accent),
          ),
          const SizedBox(height: 20),
          _dialogButton('JACK_IN', _accent,
              () => widget.onConfirm(_boardSize, _difficulty)),
        ],
      ),
    );
  }
}

// ── LAN setup dialog ──────────────────────────────────────────────────────

class _LanSetupDialog extends StatefulWidget {
  final void Function(int boardSize, int maxPlayers) onHost;
  final VoidCallback onJoin;
  const _LanSetupDialog({required this.onHost, required this.onJoin});

  @override
  State<_LanSetupDialog> createState() => _LanSetupDialogState();
}

class _LanSetupDialogState extends State<_LanSetupDialog> {
  int _boardSize = 19;
  int _maxPlayers = 2;

  static const _accent = CyberpunkColors.green;

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      title: '// LOCAL_WIRED.protocol',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dialogLabel('NETWORK_SCALE', _accent),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 9, label: Text('9×9')),
              ButtonSegment(value: 13, label: Text('13×13')),
              ButtonSegment(value: 19, label: Text('19×19')),
            ],
            selected: {_boardSize},
            onSelectionChanged: (s) => setState(() => _boardSize = s.first),
            style: _dialogSegStyle(_accent),
          ),
          const SizedBox(height: 14),
          _dialogLabel('ENTITIES', _accent),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
              ButtonSegment(value: 4, label: Text('4')),
            ],
            selected: {_maxPlayers},
            onSelectionChanged: (s) => setState(() => _maxPlayers = s.first),
            style: _dialogSegStyle(_accent),
          ),
          const SizedBox(height: 20),
          _dialogButton('OPEN_LAYER',
              _accent, () => widget.onHost(_boardSize, _maxPlayers)),
          const SizedBox(height: 8),
          _dialogButton('CONNECT_TO_LAYER',
              CyberpunkColors.cyan, widget.onJoin),
        ],
      ),
    );
  }
}

// ── Wired setup dialog ────────────────────────────────────────────────────

class _WiredSetupDialog extends StatefulWidget {
  final void Function(int boardSize, int maxPlayers) onHost;
  final VoidCallback onJoin;
  const _WiredSetupDialog({required this.onHost, required this.onJoin});

  @override
  State<_WiredSetupDialog> createState() => _WiredSetupDialogState();
}

class _WiredSetupDialogState extends State<_WiredSetupDialog> {
  int _boardSize = 19;
  int _maxPlayers = 2;

  static const _accent = Color(0xFF8B5CF6);

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      title: '// THE_WIRED.uplink',
      accent: _accent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dialogLabel('NETWORK_SCALE', _accent),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 9, label: Text('9×9')),
              ButtonSegment(value: 13, label: Text('13×13')),
              ButtonSegment(value: 19, label: Text('19×19')),
            ],
            selected: {_boardSize},
            onSelectionChanged: (s) => setState(() => _boardSize = s.first),
            style: _dialogSegStyle(_accent),
          ),
          const SizedBox(height: 14),
          _dialogLabel('ENTITIES', _accent),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
              ButtonSegment(value: 4, label: Text('4')),
            ],
            selected: {_maxPlayers},
            onSelectionChanged: (s) => setState(() => _maxPlayers = s.first),
            style: _dialogSegStyle(_accent),
          ),
          const SizedBox(height: 20),
          _dialogButton('OPEN_LAYER',
              _accent, () => widget.onHost(_boardSize, _maxPlayers)),
          const SizedBox(height: 8),
          _dialogButton('JACK_IN',
              CyberpunkColors.cyan, widget.onJoin),
        ],
      ),
    );
  }
}

