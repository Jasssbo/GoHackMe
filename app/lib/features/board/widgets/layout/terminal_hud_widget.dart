import 'package:flutter/material.dart';
import 'package:go_engine/go_engine.dart';

import '../../../../core/theme/cyberpunk_colors.dart';
import '../../../../core/theme/ui_scale.dart';

/// HUD panel displaying entities (players + subnet balances) and terminal logs.
class TerminalHudWidget extends StatelessWidget {
  final GameState state;
  final String localPlayerId;
  final List<String> logLines;
  final void Function(String)? onChatSend;
  final bool fillWidth;

  const TerminalHudWidget({
    super.key,
    required this.state,
    required this.localPlayerId,
    required this.logLines,
    this.onChatSend,
    this.fillWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fillWidth ? null : context.s(180),
      decoration: const BoxDecoration(
        color: Color(0xFF050D15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelHeader('// ENTITIES'),
          ..._playerRows(),
          const PanelDivider(),
          const PanelHeader('// LOGS'),
          const PanelDivider(),
          Expanded(child: GameTerminalLog(lines: logLines)),
          if (onChatSend != null) ...[
            const PanelDivider(),
            _ChatInput(onSend: onChatSend!),
          ],
        ],
      ),
    );
  }

  List<Widget> _playerRows() {
    const colors = [
      CyberpunkColors.stoneP1,
      CyberpunkColors.stoneP2,
      CyberpunkColors.stoneP3,
      CyberpunkColors.stoneP4,
    ];
    return state.players.map((p) {
      final isCurrent = state.currentPlayerId == p.id;
      final isLocal = p.id == localPlayerId;
      final idx = state.players.indexOf(p);
      final color = colors[idx % colors.length];
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: isCurrent
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: color.withValues(alpha: 0.85),
                    width: 2,
                  ),
                ),
                color: color.withValues(alpha: 0.10),
              )
            : const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.transparent, width: 2),
                ),
              ),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(right: 6),
              color: color.withValues(alpha: isCurrent ? 1.0 : 0.45),
            ),
            Expanded(
              child: Text(
                '${p.displayName}${isLocal ? ' [YOU]' : ''}',
                style: TextStyle(
                  color: color.withValues(alpha: isCurrent ? 1.0 : 0.65),
                  fontSize: 9.5,
                  letterSpacing: 0.8,
                  fontFamily: 'monospace',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              'SN:${state.subnetsOf(p.id)}',
              style: TextStyle(
                color: CyberpunkColors.amber
                    .withValues(alpha: isCurrent ? 0.95 : 0.65),
                fontSize: 8.5,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

class PanelHeader extends StatelessWidget {
  final String text;
  const PanelHeader(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
      child: Row(
        children: [
          Text(
            '◈  ',
            style: TextStyle(
              color: CyberpunkColors.cyanDim.withValues(alpha: 0.80),
              fontSize: 7,
            ),
          ),
          Text(
            text,
            style: TextStyle(
              color: CyberpunkColors.cyanDim.withValues(alpha: 0.95),
              fontSize: 8.5,
              letterSpacing: 2,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class PanelDivider extends StatelessWidget {
  const PanelDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: const Color(0xFF0C1814),
    );
  }
}

class GameTerminalLog extends StatelessWidget {
  final List<String> lines;
  const GameTerminalLog({super.key, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF030810),
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      child: ListView.builder(
        reverse: true,
        itemCount: lines.length,
        itemBuilder: (_, i) {
          final line = lines[lines.length - 1 - i];
          final isError = line.contains('ERROR');
          final isRecent = i == 0;

          final contentIdx = line.indexOf('] ');
          final content =
              contentIdx >= 0 ? line.substring(contentIdx + 2) : line;
          if (content.startsWith('CHAT>')) {
            final afterPrefix = content.substring(5);
            final sepIdx = afterPrefix.indexOf('>');
            if (sepIdx >= 0) {
              final senderName = afterPrefix.substring(0, sepIdx);
              final text = afterPrefix.substring(sepIdx + 1);
              final timestamp =
                  contentIdx >= 0 ? line.substring(0, contentIdx + 1) : '';
              return Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 8.5,
                    fontFamily: 'monospace',
                    height: 1.55,
                  ),
                  children: [
                    TextSpan(
                      text: '$timestamp ',
                      style: TextStyle(
                        color: CyberpunkColors.green
                            .withValues(alpha: 0.45),
                      ),
                    ),
                    TextSpan(
                      text: '[$senderName]',
                      style: TextStyle(
                        color: Colors.lightBlue.withValues(alpha: 0.90),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: ': $text',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              );
            }
          }

          return Text(
            line,
            style: TextStyle(
              color: isError
                  ? CyberpunkColors.error
                  : CyberpunkColors.green.withValues(
                      alpha:
                          isRecent ? 0.95 : (0.95 - i * 0.04).clamp(0.45, 0.95),
                    ),
              fontSize: 8.5,
              letterSpacing: 0.3,
              fontFamily: 'monospace',
              height: 1.55,
            ),
          );
        },
      ),
    );
  }
}

class _ChatInput extends StatefulWidget {
  final void Function(String) onSend;
  const _ChatInput({required this.onSend});

  @override
  State<_ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<_ChatInput> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF030810),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        children: [
          const Text(
            '>>',
            style: TextStyle(
              color: Colors.lightBlue,
              fontSize: 8.5,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8.5,
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                hintText: 'SAY...',
                hintStyle: TextStyle(
                  color: Colors.white24,
                  fontSize: 8.5,
                  fontFamily: 'monospace',
                ),
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
        ],
      ),
    );
  }
}
