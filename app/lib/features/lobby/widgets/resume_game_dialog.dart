import 'package:flutter/material.dart';
import 'package:go_engine/go_engine.dart';

import '../../../core/theme/cyberpunk_colors.dart';
import '../../../services/saved_game_service.dart';

// ── ResumeGameDialog ──────────────────────────────────────────────────────

/// Shows a list of locally-saved games and lets the user pick one to resume.
///
/// On confirm, calls [onResume] with the selected [SavedGame] and, for games
/// with more than 2 players, the slot index the joining player claims.
/// (For 2-player saves the choice is automatic once the other player joins.)
class ResumeGameDialog extends StatefulWidget {
  final void Function(SavedGame save) onResume;

  const ResumeGameDialog({super.key, required this.onResume});

  @override
  State<ResumeGameDialog> createState() => _ResumeGameDialogState();
}

class _ResumeGameDialogState extends State<ResumeGameDialog> {
  List<SavedGame>? _saves;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SavedGameService.listSaves().then((list) {
      if (mounted) setState(() { _saves = list; _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    const accent = CyberpunkColors.cyan;
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
                  // ── Header ───────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Color(0xFF0A2030),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          '// RESUME_SESSION',
                          style: TextStyle(
                            color: accent,
                            fontSize: 10,
                            letterSpacing: 2.5,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Text(
                              '[X]',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Save list ────────────────────────────────────────────
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: accent, strokeWidth: 1.5,
                              ),
                            ),
                          )
                        : (_saves == null || _saves!.isEmpty)
                            ? const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'NO_SAVED_SESSIONS_FOUND',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: CyberpunkColors.textSecondary,
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: _saves!.length,
                                itemBuilder: (_, i) => _SaveRow(
                                  save: _saves![i],
                                  onResume: () {
                                    Navigator.of(context).pop();
                                    widget.onResume(_saves![i]);
                                  },
                                  onDelete: () async {
                                    await SavedGameService.delete(_saves![i].saveId);
                                    if (mounted) {
                                      setState(() => _saves!.removeAt(i));
                                    }
                                  },
                                ),
                              ),
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

// ── _SaveRow ──────────────────────────────────────────────────────────────

class _SaveRow extends StatelessWidget {
  final SavedGame save;
  final VoidCallback onResume;
  final VoidCallback onDelete;

  const _SaveRow({
    required this.save,
    required this.onResume,
    required this.onDelete,
  });

  String _fmt(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    const accent = CyberpunkColors.cyan;
    final players = save.state.players;
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF081820), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  save.label,
                  style: const TextStyle(
                    color: accent,
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _fmt(save.savedAt),
                  style: const TextStyle(
                    color: CyberpunkColors.textSecondary,
                    fontSize: 8,
                    fontFamily: 'monospace',
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                // Player list
                Text(
                  players.map((p) => p.displayName).join(' · '),
                  style: TextStyle(
                    color: CyberpunkColors.cyanDim.withValues(alpha: 0.70),
                    fontSize: 8,
                    fontFamily: 'monospace',
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDelete,
            child: Text(
              '[DEL]',
              style: TextStyle(
                color: CyberpunkColors.error.withValues(alpha: 0.70),
                fontSize: 8,
                fontFamily: 'monospace',
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onResume,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: accent.withValues(alpha: 0.60)),
                color: accent.withValues(alpha: 0.10),
              ),
              child: const Text(
                'RESUME',
                style: TextStyle(
                  color: accent,
                  fontSize: 9,
                  letterSpacing: 1.5,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── PlayerSlotPickerDialog ────────────────────────────────────────────────

/// Shown to non-saver players joining a restored 3-4 player game.
/// They choose which player slot they occupied in the original game.
class PlayerSlotPickerDialog extends StatefulWidget {
  final List<Player> players;

  /// Indices already claimed (typically the host's slot).
  final Set<int> claimedSlots;

  final void Function(int slotIndex) onClaim;

  const PlayerSlotPickerDialog({
    super.key,
    required this.players,
    required this.claimedSlots,
    required this.onClaim,
  });

  @override
  State<PlayerSlotPickerDialog> createState() => _PlayerSlotPickerDialogState();
}

class _PlayerSlotPickerDialogState extends State<PlayerSlotPickerDialog> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    const accent = CyberpunkColors.magenta;
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
                        bottom: BorderSide(
                          color: accent.withValues(alpha: 0.30),
                          width: 1,
                        ),
                      ),
                    ),
                    child: const Text(
                      '// IDENTIFY_ENTITY',
                      style: TextStyle(
                        color: accent,
                        fontSize: 10,
                        letterSpacing: 2.5,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                    child: Text(
                      'Select the player you were in the original game:',
                      style: TextStyle(
                        color: CyberpunkColors.textSecondary.withValues(alpha: 0.80),
                        fontSize: 9,
                        fontFamily: 'monospace',
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Slot options
                  ...List.generate(widget.players.length, (i) {
                    final claimed = widget.claimedSlots.contains(i);
                    final isSelected = _selected == i;
                    return GestureDetector(
                      onTap: claimed ? null : () => setState(() => _selected = i),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 4),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: claimed
                                ? Colors.white.withValues(alpha: 0.10)
                                : isSelected
                                    ? accent
                                    : accent.withValues(alpha: 0.30),
                          ),
                          color: isSelected
                              ? accent.withValues(alpha: 0.12)
                              : Colors.transparent,
                        ),
                        child: Row(
                          children: [
                            Text(
                              '[P${i + 1}]',
                              style: TextStyle(
                                color: claimed
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : isSelected
                                        ? accent
                                        : accent.withValues(alpha: 0.55),
                                fontSize: 9,
                                fontFamily: 'monospace',
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              widget.players[i].displayName,
                              style: TextStyle(
                                color: claimed
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : Colors.white.withValues(alpha: 0.85),
                                fontSize: 10,
                                fontFamily: 'monospace',
                                letterSpacing: 1.2,
                              ),
                            ),
                            if (claimed) ...[
                              const Spacer(),
                              Text(
                                '[CLAIMED]',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  fontSize: 8,
                                  fontFamily: 'monospace',
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: GestureDetector(
                      onTap: _selected == null
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              widget.onClaim(_selected!);
                            },
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _selected != null
                              ? accent.withValues(alpha: 0.12)
                              : Colors.transparent,
                          border: Border.all(
                            color: _selected != null
                                ? accent.withValues(alpha: 0.80)
                                : Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Text(
                          'CONFIRM_IDENTITY',
                          style: TextStyle(
                            color: _selected != null
                                ? accent
                                : Colors.white.withValues(alpha: 0.25),
                            fontSize: 10,
                            letterSpacing: 2,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
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
