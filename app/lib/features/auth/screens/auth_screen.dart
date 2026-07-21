import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/cyberpunk_colors.dart';
import '../../../services/audio_service.dart';
import '../../../services/name_history_service.dart';
import '../providers/auth_provider.dart';

// ── Boot phase state machine ─────────────────────────────────────────────────

/// Tracks which visual / audio phase the terminal is currently in.
enum _BootPhase {
  /// 1-3 plays in bg; kernel log lines print one by one.
  kernelLog,

  /// 1-5 plays in bg; user-profile lines print one by one.
  userLog,

  /// Typewriter "who are you?" + name guess + input field.
  question,

  /// Sequential connect beeps (3-*); connection log lines print in lockstep.
  connecting,
}

// ── Widget ───────────────────────────────────────────────────────────────────

/// Network authentication terminal — first contact screen.
///
/// Simulates a multi-phase system boot:
///   1. Kernel log lines (audio: 1-3 fast beeps)
///   2. "logging" voice wipes the screen (1-4)
///   3. User-profile log lines (audio: 1-5 fast beeps)
///   4. "who are you?" typewriter (audio: 2)
///   5. User enters name → sequential connect beeps synced to log lines (3-*)
///   6. Navigate to lobby → greetings play (4, in LobbyScreen)
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

  // ── Boot phase ─────────────────────────────────────────────────────────────
  _BootPhase _phase = _BootPhase.kernelLog;

  // ── Phase 1: Kernel log ────────────────────────────────────────────────────
  // Timings are tuned to roughly span the duration of 1-3-bootlogging.mp3.
  // Adjust _kKernelLineMs if your audio is longer/shorter.
  // How long to pause after the screen appears before the first kernel line.
  // Increase if 1-2-booting.mp3 has a long intro; decrease for a snappier feel.
  static const int _kKernelPreDelayMs = 1200;
  // Tuned so 16 lines × 206 ms = 3296 ms ≈ 3.3 s (1-3-bootlogging.mp3).
  static const int _kKernelLineMs     = 206;

  static const _kernelLines = [
    'NAVI:OS 7.1  ·  KERNEL INIT',
    'BIOS HANDOFF  ·  COMPLETE',
    'MEMORY PROBE  ·  SECTORS 0-FF  ·  CLEAN',
    'MEMORY_MAPPED  ·  SECTORS 0-FF  ·  VERIFIED',
    'CPU SCHEDULER  ·  ONLINE',
    'INTERRUPT HANDLER  ·  MAPPED',
    'WIRED_LINK  ·  TOPOLOGY PROBE  .  .  .',
    'SUBNET DISCOVERY  .  .  .  PARTIAL',
    'FILESYSTEM MOUNT  ·  VOLUME_0  ·  OK',
    'NETWORK STACK  ·  INITIALIZED',
    'PROTOCOL STACK  ·  LOADED',
    'PROCESS TABLE  ·  ALLOCATING',
    'KNOWLEDGE_NAVIGATOR  ·  LOAD OK',
    'DAEMON_SERVICES  ·  STARTING',
    'Tachibana General Laboratories  ·  NAVIGATOR CONNECTED',
    'AUTH_SERVICE  ·  STANDING BY',
  ];
  int _kernelStep = 0;

  // ── Phase 2: User profile log ──────────────────────────────────────────────
  // Tuned so 12 lines × 175 ms = 2 100 ms ≈ 2.1 s (1-5-userlogging.mp3 + 1 s buffer).
  static const int _kUserLineMs = 175;

  static const _userLines = [
    'SYSTEM_BOOT v7.1  ·  USER PROFILE MOUNT',
    'USER_AUTH  ·  INITIATING IDENTITY PROTOCOL',
    'SCANNING LOCAL WIRED  .  .  .  ACTIVE',
    'CROSS_REF  ·  SCANNING DIGITAL FOOTPRINT  .  .  .',
    'BEHAVIORAL_MATRIX  ·  LOADING',
    'NETWORK_PRESENCE  ·  SIGNATURE DETECTED',
    'ENTITY  ·  IDENTIFIED',
    'DEVICE_FP  ·  FINGERPRINT ACQUIRED',
    'LOCATION_TRACE  ·  COORDINATES MAPPED',
    'SOCIAL_GRAPH  ·  THREADING',
    'IDENTITY_THREAD  ·  ACTIVE',
    'SURVEILLANCE_NODE  ·  WATCHING',
  ];
  int _userStep = 0;

  // ── Phase 3: "who are you?" question ──────────────────────────────────────
  static const _question = 'who are you?';
  int _questionChars = 0;

  // ── Name guesses (from history) ───────────────────────────────────────────
  List<String> _guessNames = [];
  int _guessStep = 0;
  final List<int> _guessChars = [0]; // at most 1 guess line

  // ── Phase 4: Connecting ────────────────────────────────────────────────────
  // One line per 3-beep*.mp3 file (9 files → 9 lines).
  static const _connectionLines = [
    'INITIATING_CONNECTION  ·  HANDSHAKE',
    'ROUTING  ·  LOCATING NODE',
    'AUTH_TOKEN  ·  GENERATING',
    'FIREWALL  ·  BYPASSING',
    'CHANNEL  ·  ENCRYPTED',
    'WIRED_SYNC  ·  ESTABLISHING',
    'ENTITY_BIND  ·  CONFIRMED',
    'PROTOCOL_7  ·  ACTIVE',
    'LINK  ·  ESTABLISHED',
  ];
  int _connectionStep = 0;

  // ── Input ──────────────────────────────────────────────────────────────────
  bool _inputReady = false;
  String? _warningMsg;
  // Tracks the previous text value so we can detect backspace / delete.
  String _prevText = '';

  // ── Lifecycle ──────────────────────────────────────────────────────────────

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
    // Delay until the first frame is painted so that playBootingSound (1-2)
    // fires exactly when the screen becomes visible on the device.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _runBoot();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _cursorCtrl.dispose();
    super.dispose();
  }

  // ── Sequencing ─────────────────────────────────────────────────────────────

  Future<void> _loadHistory() async {
    final names = await NameHistoryService.getNames();
    if (!mounted || names.isEmpty) return;
    final shuffled = List<String>.from(names)..shuffle(Random());
    _guessNames = shuffled.take(1).toList();
  }

  /// The full boot sequence runs as a single async chain so every `await`
  /// keeps strict ordering while never blocking the UI thread.
  Future<void> _runBoot() async {
    final audio = ref.read(audioServiceProvider);

    // ── 1-2: Screen just became visible (called via addPostFrameCallback) ─
    audio.playBootingSound();

    // Pre-delay: let the booting sound breathe before any text appears.
    await Future<void>.delayed(
      const Duration(milliseconds: _kKernelPreDelayMs),
    );
    if (!mounted) return;

    // ── 1-3: Kernel log beeps start simultaneously with the first line ────
    audio.playKernelLogSound();
    setState(() => _kernelStep = 1);

    for (int i = 1; i < _kernelLines.length; i++) {
      await Future<void>.delayed(
        const Duration(milliseconds: _kKernelLineMs),
      );
      if (!mounted) return;
      setState(() => _kernelStep = i + 1);
    }

    // ── 1-4: "logging" voice — AWAITED (wipe on return) ───────────────────
    await audio.playLoggingVoiceAndAwait();
    if (!mounted) return;

    // Clear kernel lines; switch to user-profile phase.
    setState(() {
      _phase = _BootPhase.userLog;
      _kernelStep = 0;
    });

    // ── 1-5: User profile beeps start simultaneously with the first line ──
    audio.playUserLogSound();
    setState(() => _userStep = 1);

    for (int i = 1; i < _userLines.length; i++) {
      await Future<void>.delayed(
        const Duration(milliseconds: _kUserLineMs),
      );
      if (!mounted) return;
      setState(() => _userStep = i + 1);
    }

    // Brief pause before "who are you?" appears.
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;

    setState(() => _phase = _BootPhase.question);
    _typeGuesses();
  }

  // ── Question phase helpers ─────────────────────────────────────────────────

  void _typeGuesses() {
    if (_guessNames.isEmpty) {
      _typeQuestion();
      return;
    }
    // 2: voice fires at the very first "are you X?" moment — before guess typing starts.
    ref.read(audioServiceProvider).playWhoAreYouVoice();
    _typeNextGuess(0);
  }

  void _typeNextGuess(int idx) {
    if (idx >= _guessNames.length) {
      Future<void>.delayed(const Duration(milliseconds: 280), () {
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
          Future<void>.delayed(const Duration(milliseconds: 380), () {
            if (mounted) _typeNextGuess(idx + 1);
          });
        }
      });
    }
  }

  void _typeQuestion() {
    // 2: voice fires here only when there were no guess lines.
    // If guesses existed it already fired at the start of _typeGuesses().
    if (_guessNames.isEmpty) {
      ref.read(audioServiceProvider).playWhoAreYouVoice();
    }
    for (int i = 1; i <= _question.length; i++) {
      Future.delayed(Duration(milliseconds: i * 60), () {
        if (!mounted) return;
        setState(() => _questionChars = i);
        if (i == _question.length) {
          Future<void>.delayed(const Duration(milliseconds: 420), () {
            if (mounted) setState(() => _inputReady = true);
          });
        }
      });
    }
  }

  // ── Input handling ─────────────────────────────────────────────────────────

  void _checkWarning(String value) {
    final audio = ref.read(audioServiceProvider);
    // Play the dedicated delete sound on backspace/delete; random sound otherwise.
    if (value.length < _prevText.length) {
      audio.playDeleteTypingSound();
    } else {
      audio.playRandomTypingSound();
    }
    _prevText = value;

    // Matches any code-point beyond Latin Extended-B (U+024F).
    final hasNonClassic = RegExp(r'[^\u0000-\u024F]').hasMatch(value);
    setState(() {
      _warningMsg = hasNonClassic
          ? 'WARN: emoji / non-Latin chars detected — may not render correctly'
          : null;
    });
  }

  Future<void> _enter() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty || _phase == _BootPhase.connecting) return;

    setState(() {
      _warningMsg = null;
      _phase = _BootPhase.connecting;
      _connectionStep = 0;
    });

    await ref.read(authProvider.notifier).setDisplayName(name);

    final audio = ref.read(audioServiceProvider);
    final beepCount = audio.connectBeepCount;

    for (int i = 0; i < beepCount; i++) {
      if (!mounted) return;
      setState(() => _connectionStep = i + 1);
      // Await each beep so the next line only appears when the previous ends.
      await audio.playConnectBeep(i);
    }

    if (mounted) context.go(Routes.lobby);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
              // ── Header ──────────────────────────────────────────────────
              _SystemLabel('GOHACKME:NET  ·  NODE_AUTH_TERMINAL'),
              const SizedBox(height: 6),
              Container(
                height: 1,
                color: CyberpunkColors.cyanDim.withValues(alpha: 0.22),
              ),
              const SizedBox(height: 28),

              // ── Phase 1: Kernel log ─────────────────────────────────────
              if (_phase == _BootPhase.kernelLog) ...[
                ..._kernelLines.take(_kernelStep).map(
                      (l) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          l,
                          style: TextStyle(
                            color:
                                CyberpunkColors.green.withValues(alpha: 0.75),
                            fontSize: 9.5,
                            fontFamily: 'monospace',
                            letterSpacing: 1.3,
                            height: 1.7,
                          ),
                        ),
                      ),
                    ),
                if (_kernelStep < _kernelLines.length)
                  _BlinkingCursor(
                    visible: _cursorOn,
                    color: CyberpunkColors.green,
                  ),
              ],

              // ── Phase 2-3: User profile lines ───────────────────────────
              // Hidden during 'connecting' so the terminal clears like a
              // real cls before connection log lines print in.
              if (_phase == _BootPhase.userLog ||
                  _phase == _BootPhase.question) ...[
                ..._userLines.take(_userStep).map(
                      (l) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          l,
                          style: TextStyle(
                            color:
                                CyberpunkColors.cyan.withValues(alpha: 0.60),
                            fontSize: 9.5,
                            fontFamily: 'monospace',
                            letterSpacing: 1.3,
                            height: 1.7,
                          ),
                        ),
                      ),
                    ),
                // Blinking cursor only while actively printing user lines.
                if (_phase == _BootPhase.userLog &&
                    _userStep < _userLines.length)
                  _BlinkingCursor(
                    visible: _cursorOn,
                    color: CyberpunkColors.cyan,
                  ),
              ],

              // ── Phase 3: Question + input ────────────────────────────────
              if (_phase == _BootPhase.question) ...[
                const SizedBox(height: 20),

                // "are you X?" guess lines
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
                              color: CyberpunkColors.cyanDim
                                  .withValues(alpha: 0.55),
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
                            _BlinkingCursor(
                              visible: _cursorOn,
                              color: CyberpunkColors.cyan,
                              fontSize: 14,
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
                          color:
                              CyberpunkColors.cyanDim.withValues(alpha: 0.55),
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
                      if (_questionChars < _question.length)
                        _BlinkingCursor(
                          visible: _cursorOn,
                          color: CyberpunkColors.cyan,
                          fontSize: 14,
                        ),
                    ],
                  ),

                const SizedBox(height: 4),

                // Input line — appears after question finishes typing
                if (_inputReady) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '> ',
                        style: TextStyle(
                          color:
                              CyberpunkColors.cyanDim.withValues(alpha: 0.55),
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
                          maxLength: 20,
                          buildCounter: (
                            _, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) =>
                              null,
                          onChanged: _checkWarning,
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
                              color: CyberpunkColors.textDim
                                  .withValues(alpha: 0.40),
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
                  if (_warningMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _warningMsg!,
                      style: TextStyle(
                        color: CyberpunkColors.amber.withValues(alpha: 0.80),
                        fontSize: 9,
                        letterSpacing: 1.2,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  _ConnectButton(label: 'CONNECT', onTap: _enter),
                ],
              ],

              // ── Phase 4: Connecting — connection log ─────────────────────
              if (_phase == _BootPhase.connecting) ...[
                const SizedBox(height: 16),
                ..._connectionLines.take(_connectionStep).map(
                      (l) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          l,
                          style: TextStyle(
                            color:
                                CyberpunkColors.green.withValues(alpha: 0.90),
                            fontSize: 9.5,
                            fontFamily: 'monospace',
                            letterSpacing: 1.3,
                            height: 1.7,
                          ),
                        ),
                      ),
                    ),
                if (_connectionStep < _connectionLines.length)
                  _BlinkingCursor(
                    visible: _cursorOn,
                    color: CyberpunkColors.green,
                  ),
              ],

              const Spacer(),

              // ── Footer ──────────────────────────────────────────────────
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
}

// ── _BlinkingCursor ──────────────────────────────────────────────────────────

class _BlinkingCursor extends StatelessWidget {
  final bool visible;
  final Color color;
  final double fontSize;

  const _BlinkingCursor({
    required this.visible,
    required this.color,
    this.fontSize = 9.5,
  });

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: visible ? 0.80 : 0.0,
        duration: const Duration(milliseconds: 60),
        child: Text(
          '▌',
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontFamily: 'monospace',
          ),
        ),
      );
}

// ── _SystemLabel ─────────────────────────────────────────────────────────────

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

// ── _ConnectButton ───────────────────────────────────────────────────────────

class _ConnectButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  const _ConnectButton({required this.label, this.onTap});

  @override
  State<_ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<_ConnectButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final c = _hover && enabled ? CyberpunkColors.cyan : CyberpunkColors.cyanDim;
    return MouseRegion(
      onEnter: enabled ? (_) => setState(() => _hover = true) : null,
      onExit: enabled ? (_) => setState(() => _hover = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: c.withValues(alpha: _hover && enabled ? 0.9 : 0.4),
            ),
            color: c.withValues(alpha: _hover && enabled ? 0.10 : 0.02),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: enabled ? c : c.withValues(alpha: 0.3),
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
