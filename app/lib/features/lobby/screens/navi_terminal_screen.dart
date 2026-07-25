import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/performance/performance_provider.dart';
import '../../../core/privacy/privacy_dialog.dart';
import '../../../core/theme/cyberpunk_colors.dart';

// ── NAVI response content ─────────────────────────────────────────────────

const _naviGreeting = [
  '> NAVI PROTOCOL v7.1 — CONNECTING...',
  '> CARRIER SIGNAL: DETECTED.',
  '> WIRED HANDSHAKE: COMPLETE.',
  '> ENTITY LINK: ESTABLISHED.',
  '',
  '  No matter where you are,',
  '  everyone is always connected.',
  '',
  '  I am NAVI. I am your guide to the Wired.',
  '  You are holding a protocol — Go,',
  '  played as a conflict between entities across the network.',
  '  The board is real. The attacks are real.',
  '  The separation between game and network is an illusion.',
  '',
  '  Type [help] if you feel lost.',
  '  Type [exit] to jack out.',
  '',
];

const Map<String, List<String>> _naviResponses = {
  'help': [
    '> AVAILABLE QUERIES:',
    '',
    '  [1]       — what is GoHackMe?',
    '  [2]       — how do i play?',
    '  [3]       — what are the attacks?',
    '  [4]       — how do i play with others?',
    '  [lang]    — language settings (lang en/es/ja/zh)',
    '  [privacy] — view zero-data privacy policy',
    '  [lain]    — what is the wired?',
    '  [tos]     — terms of service / legal protocol',
    '',
  ],
  '1': [
    '> LOADING: PROTOCOL_CONTEXT...',
    '',
    '  GoHackMe exists on two layers simultaneously.',
    '',
    '  THE WIRED — the substrate:',
    '  The Wired is the network beneath the network.',
    '  The place where consciousness, data, and identity dissolve into one.',
    '  It predates the internet. It predates language.',
    '  It is where this game is played.',
    '',
    '  THE BOARD — the protocol:',
    '  Go is the oldest strategy game on Earth.',
    '  Entities alternate placing stones on a grid,',
    '  claiming territory by surrounding it.',
    '  No randomness. No hidden information. Infinite depth.',
    '  Each intersection is a node.',
    '  Each group of stones, a subnet.',
    '  Capture or be captured.',
    '',
    '  THE HACKS — the breach:',
    '  You earn subnets by controlling the board.',
    '  Spend them to run attack scripts against opponents.',
    '  DDOS. WORM. BACKDOOR. PSYCHE.',
    '  Defend your firewall. Breach theirs.',
    '  The board is both the game and the battlefield.',
    '',
  ],
  '2': [
    '> LOADING: RULESET_v7.1...',
    '',
    '  Standard Go with a hacker layer on top.',
    '',
    '  CORE RULES:',
    '  • Entities alternate placing stones on intersections.',
    '  • A group with no empty adjacent points (liberties)',
    '    is captured and removed from the board.',
    '  • You cannot recreate a previous board state (superko).',
    '  • PASS ends your turn.',
    '  • Two consecutive passes end the game.',
    '',
    '  BOARD SIZES:',
    '  • 9×9  — fast. aggressive. good for learning.',
    '  • 13×13 — medium depth.',
    '  • 19×19 — full protocol. the real Wired.',
    '',
    '  PLAYERS: 2 to 4 entities per session.',
    '',
    '  SCORING (area / Chinese rules):',
    '  Count your stones + empty intersections you fully surround.',
    '  Most territory wins.',
    '',
    '  SUBNETS:',
    '  • +1 SN each turn automatically.',
    '  • +1 SN for placing on a star point (hoshi).',
    '  • +1 SN per enemy stone captured.',
    '  Subnets fund your attacks. Hoard them wisely.',
    '',
    '  TURN TIMER:',
    '  Each entity has 15 seconds per turn.',
    '  Exceed it and the system will auto-skip your turn.',
    '  The Wired waits for no one.',
    '',
  ],
  '3': [
    '> LOADING: ATTACK_CODEX_v7.1...',
    '',
    '  All attacks are executed during the attack phase,',
    '  before you place your stone.',
    '  You may chain multiple attacks in one turn.',
    '',
    '  BACKDOOR.sh      — 3 SN',
    '  Self-exploit. Place 2 stones this turn instead of 1.',
    '',
    '  PATCH.sh         — 4 SN',
    '  Apply security patch. Block next incoming attack. Stacks.',
    '',
    '  WORM.sh          — 4 SN',
    '  Inject worm. Overwrite one enemy stone with yours.',
    '  Target a specific enemy stone on the board.',
    '',
    '  TROJAN.sh        — 5 SN',
    '  Deploy trojan. Steal half their subnets.',
    '  You gain what they lose.',
    '',
    '  KNIGHTS_EYE.sh   — 6 SN',
    '  Deploy trap on your own stone.',
    '  If that stone is captured, it reclaims itself',
    '  and captures all adjacent enemy stones.',
    '',
    '  DDOS.sh          — 7 SN',
    '  Flood target node. Target skips next placement.',
    '',
    '  MITM.sh          — 8 SN',
    '  Hijack next turn. You place the enemy\'s stone.',
    '  They skip their attack phase.',
    '',
    '  PSYCHE.sh        — 10 SN',
    '  Initiate countdown protocol.',
    '  All enemies must act within 5 seconds',
    '  for 3 turns or be auto-skipped.',
    '  Use when you\'re winning. Make them panic.',
    '',
  ],
  '4': [
    '> LOADING: NETWORK_PROTOCOLS...',
    '',
    '  Three ways to run a session:',
    '',
    '  CLOSED_CIRCUIT — solo:',
    '  • 1v1 against a local bot entity.',
    '  • No network required.',
    '  • LAYER_1 — beginner bot. forgiving.',
    '  • LAYER_2 — intermediate bot. it adapts.',
    '  • Full attack system active.',
    '  • 15-second turn timer enforced.',
    '',
    '  LOCAL_WIRED — LAN:',
    '  • All entities must share the same local network.',
    '  • One entity opens a LAYER (TCP server on their device).',
    '  • Others are discovered automatically — no IPs needed.',
    '  • 2 to 4 players. 15-second turn timer.',
    '  • Zero latency. Fully isolated from the internet.',
    '',
    '  THE_WIRED — online:',
    '  • Connects to a remote server over WebSocket.',
    '  • One entity opens a LAYER and receives a room code.',
    '  • Share the code. Others jack in with it.',
    '  • 2 to 4 players. 15-second turn timer.',
    '  • Works anywhere. The Wired has no walls.',
    '',
  ],
  'lain': [
    '> ACCESSING: /lain/iwakura.log',
    '',
    '  Present day. Present time.',
    '',
    '  MESSAGE FROM: Chisa Yomoda',
    '',
    '  "...I have only given up my body..."',
    '  "...I can use this system to explain to you..."',
    '  "...that I am still alive..."',
    '  "...Here, there is a God."',
    '',
  ],
  'tos': [
    '> LOADING: LEGAL_PROTOCOL_v1.0...',
    '',
    '  TERMS OF SERVICE — GoHackMe',
    '  Last updated: 2026',
    '',
    '  — ACCEPTANCE —',
    '  By jacking in you agree to these terms.',
    '  If you do not agree, jack out now.',
    '',
    '  — THE SOFTWARE —',
    '  GoHackMe is provided free of charge, as-is.',
    '  Source code is available under the MIT License.',
    '  No warranty is expressed or implied.',
    '  We are not liable for any damages arising from use.',
    '',
    '  — ONLINE MULTIPLAYER (THE WIRED) —',
    '  The Wired mode transmits your display name and',
    '  your device\'s IP address to our game server.',
    '  Your IP is used only to pin your country on the',
    '  globe widget. Precise coordinates are never stored.',
    '  All server data is deleted within 2 hours.',
    '',
    '  — CHAT —',
    '  In-game chat is visible to all entities in your room.',
    '  You agree not to transmit:',
    '  • Hate speech or harassment of any kind.',
    '  • Personal data of others without their consent.',
    '  • Content that is illegal in your jurisdiction.',
    '  We reserve the right to block entities who violate',
    '  these rules without prior notice.',
    '',
    '  — USER CONTENT —',
    '  Display names and chat messages are user-generated.',
    '  You are solely responsible for what you transmit.',
    '  We do not moderate content in real time.',
    '',
    '  — CHILDREN —',
    '  GoHackMe is rated 12+.',
    '  Do not use The Wired mode if you are under 13 (US)',
    '  or under 16 (EU) without parental consent.',
    '',
    '  — CHANGES —',
    '  These terms may be updated at any time.',
    '  Continued use after an update means acceptance.',
    '',
    '  — GOVERNING LAW —',
    '  These terms are governed by applicable local law.',
    '  Disputes shall be resolved in your jurisdiction.',
    '',
    '  — PUBLIC LEGAL & PRIVACY PROTOCOL —',
    '  Public Web Privacy Policy:',
    '  https://jasssbo.github.io/GoHackMe/privacy.html',
    '',
    '  — CONTACT & ISSUES —',
    '  To report a violation, request data purge, or open an issue:',
    '  https://github.com/Jasssbo/GoHackMe_Flutter',
    '',
    '  End of protocol. The Wired remembers.',
    '',
  ],
};

// ── Screen ────────────────────────────────────────────────────────────────

class NaviTerminalScreen extends ConsumerStatefulWidget {
  const NaviTerminalScreen({super.key});

  @override
  ConsumerState<NaviTerminalScreen> createState() => _NaviTerminalScreenState();
}

class _NaviTerminalScreenState extends ConsumerState<NaviTerminalScreen> {
  final List<_TerminalLine> _lines = [];
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _inputCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _inputEnabled = false;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _typeLines(_naviGreeting, onDone: () {
      if (mounted) setState(() => _inputEnabled = true);
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Output helpers ────────────────────────────────────────────────────────

  void _appendLine(String text, {_LineKind kind = _LineKind.navi}) {
    if (!mounted) return;
    setState(() => _lines.add(_TerminalLine(text: text, kind: kind)));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _typeLines(
    List<String> lines, {
    Duration lineDelay = const Duration(milliseconds: 55),
    VoidCallback? onDone,
  }) async {
    _isTyping = true;
    for (final line in lines) {
      if (!mounted) return;
      _appendLine(line);
      await Future<void>.delayed(lineDelay);
    }
    _isTyping = false;
    onDone?.call();
  }

  // ── Input handling ────────────────────────────────────────────────────────

  void _submit() {
    final raw = _inputCtrl.text.trim().toLowerCase();
    if (raw.isEmpty) return;

    final display = _inputCtrl.text.trim();
    _inputCtrl.clear();

    _appendLine('> $display', kind: _LineKind.user);

    if (raw == 'exit') {
      _appendLine('', kind: _LineKind.navi);
      _appendLine('  Jacking out. See you in the Wired.', kind: _LineKind.navi);
      _appendLine('', kind: _LineKind.navi);
      setState(() => _inputEnabled = false);
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }

    if (raw == 'privacy') {
      PrivacyNoticeDialog.show(context);
      _appendLine('  Opening ZERO_DATA_PRIVACY_POLICY modal...', kind: _LineKind.navi);
      _focusNode.requestFocus();
      return;
    }

    if (raw.startsWith('lang')) {
      final parts = raw.split(RegExp(r'\s+'));
      if (parts.length > 1) {
        final code = parts[1];
        final lang = AppLanguage.fromCode(code);
        ref.read(localeProvider.notifier).setLanguage(lang);
        _appendLine('  LANGUAGE_SET :: ${lang.label} (${lang.code})', kind: _LineKind.navi);
        _appendLine('  UI strings updated to ${lang.nativeName}.', kind: _LineKind.navi);
      } else {
        _appendLine('  SUPPORTED LANGUAGES:', kind: _LineKind.navi);
        for (final l in AppLanguage.values) {
          _appendLine('  • ${l.code.padRight(4)} — ${l.label} (${l.nativeName})', kind: _LineKind.navi);
        }
        _appendLine('  Type [lang <code>] to switch language.', kind: _LineKind.navi);
      }
      _focusNode.requestFocus();
      return;
    }

    if (raw.startsWith('perf')) {
      final parts = raw.split(RegExp(r'\s+'));
      if (parts.length > 1) {
        final mode = PerformanceMode.fromCode(parts[1]);
        ref.read(performanceModeProvider.notifier).setMode(mode);
        _appendLine('  PERFORMANCE_MODE :: ${mode.label}', kind: _LineKind.navi);
        _appendLine('  ${mode.description}', kind: _LineKind.navi);
      } else {
        final current = ref.read(performanceModeProvider);
        _appendLine('  CURRENT PERFORMANCE MODE: ${current.label}', kind: _LineKind.navi);
        _appendLine('  • high  — Full 60 FPS ambient pulse animations', kind: _LineKind.navi);
        _appendLine('  • save  — Power-save static glow mode (0 FPS GPU idle)', kind: _LineKind.navi);
        _appendLine('  Type [perf high] or [perf save] to toggle.', kind: _LineKind.navi);
      }
      _focusNode.requestFocus();
      return;
    }

    final response = _naviResponses[raw];
    if (response != null) {
      setState(() => _inputEnabled = false);
      _typeLines(response, onDone: () {
        if (mounted) {
          setState(() => _inputEnabled = true);
          _focusNode.requestFocus();
        }
      });
    } else {
      _appendLine(
        '  Unknown query. Type [help] for available commands.',
        kind: _LineKind.navi,
      );
      _appendLine('', kind: _LineKind.navi);
      _focusNode.requestFocus();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberpunkColors.background,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!_focusNode.hasFocus && _inputEnabled) {
            _focusNode.requestFocus();
          }
        },
        child: SafeArea(
          child: Column(
            children: [
              // ── Terminal header bar ────────────────────────────────────
              _TerminalHeader(
                onClose: () => Navigator.of(context).pop(),
              ),
              // ── Output area ────────────────────────────────────────────
              Expanded(
                child: ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  itemCount: _lines.length,
                  itemBuilder: (context, i) => _LineWidget(line: _lines[i]),
                ),
              ),
              // ── Blinking cursor row when typing ───────────────────────
              if (_isTyping) const _CursorRow(),
              // ── Input row ─────────────────────────────────────────────
              _InputRow(
                controller: _inputCtrl,
                focusNode: _focusNode,
                enabled: _inputEnabled,
                onSubmit: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────

enum _LineKind { navi, user }

class _TerminalLine {
  final String text;
  final _LineKind kind;
  const _TerminalLine({required this.text, required this.kind});
}

class _TerminalHeader extends StatelessWidget {
  final VoidCallback onClose;
  const _TerminalHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: CyberpunkColors.amber.withValues(alpha: 0.06),
        border: Border(
          bottom: BorderSide(
            color: CyberpunkColors.amber.withValues(alpha: 0.30),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            'NAVI://terminal',
            style: TextStyle(
              color: CyberpunkColors.amber.withValues(alpha: 0.90),
              fontSize: 9.5,
              letterSpacing: 2.5,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onClose,
            child: const Text(
              '[×]',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                letterSpacing: 1,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineWidget extends StatelessWidget {
  final _TerminalLine line;
  const _LineWidget({required this.line});

  @override
  Widget build(BuildContext context) {
    final isUser = line.kind == _LineKind.user;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: Text(
        line.text,
        style: TextStyle(
          color: isUser
              ? CyberpunkColors.cyan.withValues(alpha: 0.90)
              : CyberpunkColors.amber.withValues(alpha: 0.85),
          fontSize: 11,
          fontFamily: 'monospace',
          height: 1.65,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _CursorRow extends StatefulWidget {
  const _CursorRow();

  @override
  State<_CursorRow> createState() => _CursorRowState();
}

class _CursorRowState extends State<_CursorRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: AnimatedBuilder(
        animation: _blink,
        builder: (_, __) => Opacity(
          opacity: _blink.value > 0.5 ? 1.0 : 0.0,
          child: Text(
            '▌',
            style: TextStyle(
              color: CyberpunkColors.amber.withValues(alpha: 0.80),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onSubmit;

  const _InputRow({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: CyberpunkColors.amber.withValues(alpha: 0.20),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            '> ',
            style: TextStyle(
              color: CyberpunkColors.amber.withValues(alpha: enabled ? 0.90 : 0.30),
              fontSize: 12,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              autofocus: true,
              style: TextStyle(
                color: CyberpunkColors.cyan.withValues(alpha: 0.90),
                fontSize: 12,
                fontFamily: 'monospace',
                letterSpacing: 0.4,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: enabled ? 'type a command...' : '',
                hintStyle: TextStyle(
                  color: CyberpunkColors.amber.withValues(alpha: 0.20),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              onSubmitted: (_) => enabled ? onSubmit() : null,
              cursorColor: CyberpunkColors.amber,
              cursorWidth: 7,
              cursorHeight: 13,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: enabled ? onSubmit : null,
            child: Text(
              '[SEND]',
              style: TextStyle(
                color: enabled
                    ? CyberpunkColors.amber.withValues(alpha: 0.65)
                    : CyberpunkColors.amber.withValues(alpha: 0.18),
                fontSize: 9,
                letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
