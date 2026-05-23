import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/cyberpunk_colors.dart';
import '../../../services/name_history_service.dart';
import '../providers/auth_provider.dart';

/// Network authentication terminal — first contact screen.
/// Simulates a system boot sequence, then asks "who are you?" character
/// by character before revealing the input prompt.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with TickerProviderStateMixin {
  final _ctrl = TextEditingController();
  late final AnimationController _cursorCtrl;
  bool _cursorOn = true;

  // ── Boot lines ────────────────────────────────────────────────────────────
  static const _bootLines = [
    'NAVI:OS 7.1  ·  KERNEL LOAD OK',
    'WIRED_LINK  ·  TOPOLOGY PROBE...',
    'SUBNET DISCOVERY  .  .  .  PARTIAL',
    'MEMORY_MAPPED  ·  SECTORS 0-FF  ·  CLEAN',
    'Tachibana General Laboratories  ·  KNOWLEDGE NAVIGATOR CONNECTED',
    'AUTH_SERVICE  ·  READY',
  ];
  int _bootStep = 0;

  // ── Typewriter question ───────────────────────────────────────────────────
  static const _question = 'who are you?';
  bool _questionVisible = false; // blank line separator shown
  int _questionChars = 0;        // how many chars of question are visible

  // ── Name guesses (from history) ──────────────────────────────────────────
  List<String> _guessNames = [];       // up to 1 randomly picked past name
  int _guessStep = 0;                   // how many guess lines are active/done
  final List<int> _guessChars = [0];    // chars typed per guess line

  // ── Input ─────────────────────────────────────────────────────────────────
  bool _inputReady = false;

  @override
  void initState() {
    super.initState();
    _cursorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    )..addStatusListener((s) {
        if (!mounted) return;
        if (s == AnimationStatus.completed) {
          setState(() => _cursorOn = false);
          _cursorCtrl.reverse();
        } else if (s == AnimationStatus.dismissed) {
          setState(() => _cursorOn = true);
          _cursorCtrl.forward();
        }
      })
      ..forward();
    _loadHistory();
    _runBoot();
  }

  // ── Sequencing ────────────────────────────────────────────────────────────

  Future<void> _loadHistory() async {
    final names = await NameHistoryService.getNames();
    if (!mounted || names.isEmpty) return;
    final shuffled = List<String>.from(names)..shuffle(Random());
    _guessNames = shuffled.take(1).toList();
  }

  void _runBoot() {
    for (int i = 0; i < _bootLines.length; i++) {
      Future.delayed(Duration(milliseconds: 350 + i * 340), () {
        if (!mounted) return;
        setState(() => _bootStep = i + 1);
        if (i == _bootLines.length - 1) _pauseThenQuestion();
      });
    }
  }

  void _pauseThenQuestion() {
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() => _questionVisible = true);
      _typeGuesses();
    });
  }

  void _typeQuestion() {
    for (int i = 1; i <= _question.length; i++) {
      Future.delayed(Duration(milliseconds: i * 60), () {
        if (!mounted) return;
        setState(() => _questionChars = i);
        if (i == _question.length) {
          Future.delayed(const Duration(milliseconds: 420), () {
            if (mounted) setState(() => _inputReady = true);
          });
        }
      });
    }
  }

  void _typeGuesses() {
    if (_guessNames.isEmpty) {
      _typeQuestion();
      return;
    }
    _typeNextGuess(0);
  }

  void _typeNextGuess(int idx) {
    if (idx >= _guessNames.length) {
      Future.delayed(const Duration(milliseconds: 280), () {
        if (mounted) _typeQuestion();
      });
      return;
    }
    final text = 'are you ${_guessNames[idx]}?';
    setState(() => _guessStep = idx + 1);
    for (int i = 1; i <= text.length; i++) {
      Future.delayed(Duration(milliseconds: i * 55), () {
        if (!mounted) return;
        setState(() => _guessChars[idx] = i);
        if (i == text.length) {
          Future.delayed(const Duration(milliseconds: 380), () {
            if (mounted) _typeNextGuess(idx + 1);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _cursorCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberpunkColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(36, 48, 36, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────────
              _SystemLabel('GOHACKME:NET  ·  NODE_AUTH_TERMINAL'),
              const SizedBox(height: 6),
              Container(
                height: 1,
                color: CyberpunkColors.cyanDim.withValues(alpha: 0.22),
              ),
              const SizedBox(height: 28),

              // ── Boot lines ────────────────────────────────────────────
              ..._bootLines.take(_bootStep).map(
                    (l) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        l,
                        style: TextStyle(
                          color: CyberpunkColors.green.withValues(alpha: 0.75),
                          fontSize: 9.5,
                          fontFamily: 'monospace',
                          letterSpacing: 1.3,
                          height: 1.7,
                        ),
                      ),
                    ),
                  ),

              // Blinking cursor while boot is running
              if (_bootStep < _bootLines.length)
                AnimatedOpacity(
                  opacity: _cursorOn ? 0.80 : 0.0,
                  duration: const Duration(milliseconds: 60),
                  child: Text(
                    '▌',
                    style: TextStyle(
                      color: CyberpunkColors.green.withValues(alpha: 0.75),
                      fontSize: 9.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),

              // ── Post-boot: question + input ───────────────────────────
              if (_questionVisible) ...[
                const SizedBox(height: 20),

                // ── "are you X?" guess lines ───────────────────────────
                for (int gi = 0; gi < _guessStep; gi++) ...[  
                  Builder(builder: (context) {
                    final guessText = 'are you ${_guessNames[gi]}?';
                    final visible = _guessChars[gi];
                    final isTyping = visible < guessText.length;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '> ',
                            style: TextStyle(
                              color: CyberpunkColors.cyanDim.withValues(alpha: 0.55),
                              fontSize: 14,
                              fontFamily: 'monospace',
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            guessText.substring(0, visible),
                            style: TextStyle(
                              color: CyberpunkColors.textPrimary
                                  .withValues(alpha: 0.70),
                              fontSize: 14,
                              fontFamily: 'monospace',
                              letterSpacing: 1.0,
                            ),
                          ),
                          if (isTyping)
                            AnimatedOpacity(
                              opacity: _cursorOn ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 60),
                              child: const Text(
                                '▌',
                                style: TextStyle(
                                  color: CyberpunkColors.cyan,
                                  fontSize: 14,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],

                // "who are you?" typed out
                if (_questionChars > 0)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '> ',
                        style: TextStyle(
                          color: CyberpunkColors.cyanDim.withValues(alpha: 0.55),
                          fontSize: 14,
                          fontFamily: 'monospace',
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        _question.substring(0, _questionChars),
                        style: const TextStyle(
                          color: CyberpunkColors.textPrimary,
                          fontSize: 14,
                          fontFamily: 'monospace',
                          letterSpacing: 1.0,
                        ),
                      ),
                      // Cursor while typing the question
                      if (_questionChars < _question.length)
                        AnimatedOpacity(
                          opacity: _cursorOn ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 60),
                          child: const Text(
                            '▌',
                            style: TextStyle(
                              color: CyberpunkColors.cyan,
                              fontSize: 14,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                    ],
                  ),

                const SizedBox(height: 4),

                // ── Input line ─────────────────────────────────────────
                if (_inputReady) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '> ',
                        style: TextStyle(
                          color: CyberpunkColors.cyanDim.withValues(alpha: 0.55),
                          fontSize: 14,
                          fontFamily: 'monospace',
                          letterSpacing: 1,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          autofocus: true,
                          cursorColor: CyberpunkColors.cyan,
                          cursorWidth: 2,
                          style: const TextStyle(
                            color: CyberpunkColors.textPrimary,
                            fontSize: 14,
                            letterSpacing: 2.0,
                            fontFamily: 'monospace',
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            hintText: '...',
                            hintStyle: TextStyle(
                              color: CyberpunkColors.textDim.withValues(alpha: 0.40),
                              fontSize: 14,
                              letterSpacing: 2,
                              fontFamily: 'monospace',
                            ),
                          ),
                          onSubmitted: (_) => _enter(),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    height: 1,
                    color: CyberpunkColors.cyanDim.withValues(alpha: 0.25),
                  ),
                  const SizedBox(height: 32),
                  _ConnectButton(label: 'CONNECT', onTap: _enter),
                ],
              ],

              const Spacer(),

              // ── Footer ────────────────────────────────────────────────
              Row(
                children: [
                  _SystemLabel('PROTOCOL_7  ·  THE WIRED'),
                  const Spacer(),
                  _SystemLabel('v0.1.0-α'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _enter() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    ref.read(authProvider.notifier).setDisplayName(name);
    context.go(Routes.lobby);
  }
}

// ── _SystemLabel ────────────────────────────────────────────────────────────

class _SystemLabel extends StatelessWidget {
  final String text;
  const _SystemLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          color: CyberpunkColors.cyanDim.withValues(alpha: 0.50),
          fontSize: 8.5,
          letterSpacing: 2,
          fontFamily: 'monospace',
        ),
      );
}

// ── _ConnectButton ──────────────────────────────────────────────────────────

class _ConnectButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _ConnectButton({required this.label, required this.onTap});

  @override
  State<_ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<_ConnectButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = _hover ? CyberpunkColors.cyan : CyberpunkColors.cyanDim;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: c.withValues(alpha: _hover ? 0.9 : 0.4)),
            color: c.withValues(alpha: _hover ? 0.10 : 0.02),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: c,
                fontSize: 10,
                letterSpacing: 5,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
