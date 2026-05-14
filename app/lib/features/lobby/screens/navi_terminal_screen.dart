import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/cyberpunk_colors.dart';

// ── NAVI response content ─────────────────────────────────────────────────

const _naviGreeting = [
  '> NAVI PROTOCOL v1.0 — INITIALIZING...',
  '> ENTITY LINK: ESTABLISHED.',
  '',
  '  Hey. You made it into the Wired.',
  '  I\'m NAVI — your guide in this network.',
  '',
  '  Type [help] to see what I can tell you.',
  '  Type [exit] when you\'re done.',
  '',
];

const Map<String, List<String>> _naviResponses = {
  'help': [
    '> AVAILABLE_QUERIES:',
    '',
    '  [what is this?]          — about GoHackMe and the Wired',
    '  [how can i play]         — rules of this version of Go',
    '  [how can i play with others?] — online & LAN multiplayer',
    '',
  ],
  'what is this?': [
    '> LOADING: PROTOCOL_CONTEXT...',
    '',
    '  GoHackMe exists in two layers simultaneously.',
    '',
    '  THE WIRED — the ideal:',
    '  Go is one of the oldest strategy games on Earth.',
    '  Two players place stones on a grid, claiming territory.',
    '  Simple rules. Infinite depth. No randomness.',
    '  The Wired is the network that connects all consciousness —',
    '  the place where information has no physical boundary.',
    '  GoHackMe is a match between entities on that network.',
    '',
    '  THE REAL — the hackers layer:',
    '  Every stone placement is also a network move.',
    '  You earn "subnets" by capturing territory and star-points.',
    '  Subnets fuel attacks — disruptions sent to your opponent\'s',
    '  connection, applied as game effects on their stones.',
    '  Defend your firewall. Breach theirs.',
    '',
    '  The board is both battlefield and protocol.',
    '',
  ],
  'how can i play': [
    '> LOADING: RULESET_v7...',
    '',
    '  This is standard Go with a hacker layer on top.',
    '',
    '  CORE RULES:',
    '  • Players alternate placing stones on intersections.',
    '  • A stone group with no liberties (empty adjacent points)',
    '    is captured and removed from the board.',
    '  • You may not recreate a previous board state (superko).',
    '  • Passing ends your turn. Two consecutive passes end the game.',
    '',
    '  SCORING:',
    '  Area scoring (Chinese rules) — count your stones plus',
    '  the empty intersections you fully surround.',
    '  Most territory wins.',
    '',
    '  SUBNETS & ATTACKS:',
    '  • Placing on a star point earns +1 subnet.',
    '  • Each stone you capture earns +1 subnet.',
    '  • You start with 1 subnet per turn.',
    '  • Spend subnets to launch attacks against opponents.',
    '  • Attacks apply effects: freeze, scatter, or disrupt.',
    '  • A firewall stone protects its group from captures',
    '    until the firewall is breached by an attack.',
    '',
    '  Play the board. Hack the network.',
    '',
  ],
  'how can i play with others?': [
    '> LOADING: NETWORK_PROTOCOLS...',
    '',
    '  GoHackMe supports two ways to connect with other entities:',
    '',
    '  LOCAL_WIRED (LAN):',
    '  • All players must be on the same local network.',
    '  • One player opens a LAYER (hosts a server on their device).',
    '  • Others connect automatically via LAN discovery.',
    '  • No internet required. Fast, zero-latency, fully isolated.',
    '  • Best for playing with someone in the same physical space.',
    '',
    '  THE_WIRED (WebRTC / Internet):',
    '  • Peer-to-peer connection — no central server needed.',
    '  • One player opens a LAYER and receives a handshake code.',
    '  • Share that code with your opponent (any channel — message,',
    '    voice, carrier pigeon — doesn\'t matter).',
    '  • They enter the code to jack in and the connection forms.',
    '  • Works across the internet without port forwarding.',
    '  • WebRTC handles NAT traversal behind the scenes.',
    '',
    '  Both modes are available from the main screen.',
    '',
  ],
};

// ── Screen ────────────────────────────────────────────────────────────────

class NaviTerminalScreen extends StatefulWidget {
  const NaviTerminalScreen({super.key});

  @override
  State<NaviTerminalScreen> createState() => _NaviTerminalScreenState();
}

class _NaviTerminalScreenState extends State<NaviTerminalScreen> {
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
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberpunkColors.background,
      body: SafeArea(
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
            child: Text(
              '[×]',
              style: TextStyle(
                color: CyberpunkColors.amber.withValues(alpha: 0.55),
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
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: (event) {
                if (enabled &&
                    event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter) {
                  onSubmit();
                }
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
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
