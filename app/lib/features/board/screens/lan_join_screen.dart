import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/cyberpunk_colors.dart';
import '../../../core/widgets/glitch_overlay.dart';
import '../../../services/lan_discovery_service.dart';

// ── LanJoinScreen ──────────────────────────────────────────────────────────

/// Scans for LAN rooms via UDP broadcast and lets the user pick one to join.
class LanJoinScreen extends ConsumerStatefulWidget {
  const LanJoinScreen({super.key});

  @override
  ConsumerState<LanJoinScreen> createState() => _LanJoinScreenState();
}

class _LanJoinScreenState extends ConsumerState<LanJoinScreen> {
  List<LanRoom>? _rooms;
  bool _scanning = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _errorMsg = null;
    });
    try {
      final found = await scanForLanRooms();
      if (!mounted) return;
      setState(() {
        _rooms = found;
        _scanning = false;
        if (found.isEmpty) _errorMsg = 'NO_ROOMS_FOUND';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _errorMsg = 'SCAN_ERROR: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CyberpunkColors.background,
      body: GlitchOverlay(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ─────────────────────────────────────────────
                Row(
                  children: [
                    InkWell(
                      onTap: () => context.pop(),
                      child: const Text(
                        '< BACK',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          letterSpacing: 2,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  '// LAN_SCAN.sh',
                  style: TextStyle(
                    color: CyberpunkColors.cyan,
                    fontSize: 20,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
                const Text(
                  'Scanning local network for open rooms…',
                  style: TextStyle(
                    color: CyberpunkColors.textDim,
                    fontSize: 10,
                    letterSpacing: 1,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 24),

                // ── Scan status ────────────────────────────────────────
                if (_scanning)
                  Row(
                    children: const [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: CyberpunkColors.cyan,
                          strokeWidth: 1.5,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'SCANNING…',
                        style: TextStyle(
                          color: CyberpunkColors.cyan,
                          fontSize: 11,
                          letterSpacing: 2,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),

                if (!_scanning && _errorMsg != null)
                  Text(
                    _errorMsg!,
                    style: const TextStyle(
                      color: CyberpunkColors.error,
                      fontSize: 11,
                      letterSpacing: 1,
                      fontFamily: 'monospace',
                    ),
                  ),

                // ── Room list ──────────────────────────────────────────
                if (_rooms != null && _rooms!.isNotEmpty) ...[
                  const Text(
                    '> ROOMS_FOUND:',
                    style: TextStyle(
                      color: CyberpunkColors.green,
                      fontSize: 10,
                      letterSpacing: 1,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._rooms!.map(_RoomCard.new),
                ],

                const Spacer(),

                // ── Rescan button ──────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _scanning ? null : _scan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          CyberpunkColors.cyan.withValues(alpha: 0.12),
                      foregroundColor: CyberpunkColors.cyan,
                      side: BorderSide(
                        color: CyberpunkColors.cyan
                            .withValues(alpha: _scanning ? 0.3 : 0.8),
                      ),
                    ),
                    child: const Text('RESCAN.sh'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── _RoomCard ──────────────────────────────────────────────────────────────

class _RoomCard extends StatelessWidget {
  final LanRoom room;
  const _RoomCard(this.room);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => context.push(Routes.lanGame, extra: {'room': room}),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(
              color: CyberpunkColors.cyanDim.withValues(alpha: 0.5),
            ),
            color: CyberpunkColors.cyanDim.withValues(alpha: 0.04),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ROOM:${room.roomCode}',
                      style: const TextStyle(
                        color: CyberpunkColors.cyan,
                        fontSize: 13,
                        letterSpacing: 2,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'HOST: ${room.hostName}  '
                      '${room.boardSize}×${room.boardSize}  '
                      '${room.currentPlayers}/${room.maxPlayers} NODES',
                      style: const TextStyle(
                        color: CyberpunkColors.textSecondary,
                        fontSize: 9,
                        letterSpacing: 1,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                '[JOIN >>]',
                style: TextStyle(
                  color: CyberpunkColors.green,
                  fontSize: 10,
                  letterSpacing: 1.5,
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
