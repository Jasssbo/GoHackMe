import 'package:flutter/material.dart';

import '../theme/cyberpunk_colors.dart';

/// Cyberpunk-styled Zero-Data Privacy Notice dialog satisfying
/// Apple App Store Review Guideline 5.1.1 and Google Play Policy.
class PrivacyNoticeDialog extends StatelessWidget {
  const PrivacyNoticeDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const PrivacyNoticeDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF070C10),
      shape: const RoundedRectangleBorder(),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          border: Border.all(color: CyberpunkColors.green, width: 1),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '// PRIVACY_POLICY :: ZERO_DATA_PROTOCOL',
                    style: TextStyle(
                      color: CyberpunkColors.green,
                      fontSize: 12,
                      letterSpacing: 1.5,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Text(
                      '[X]',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: CyberpunkColors.green.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              const Text(
                '1. ZERO DATA COLLECTION\n'
                'GoHackMe does not track, collect, store, or sell any personal data, advertising identifiers (IDFA/GAID), analytics telemetry, or user location.\n\n'
                '2. LOCAL STORAGE ONLY\n'
                'All game saves and settings remain strictly on your local device.\n\n'
                '3. MULTIPLAYER PROTOCOL (THE WIRED)\n'
                'In online / LAN multiplayer modes, temporary session data (display name, move coordinates, and self-reported country node location) is held in RAM only and automatically erased within 2 hours. No third-party IP geolocation API pings are performed.\n\n'
                '4. NO THIRD-PARTY TRACKERS\n'
                'No third-party advertising, analytics, or behavioral tracking SDKs are bundled in this binary.\n\n'
                '5. PUBLIC WEB PRIVACY POLICY\n'
                'https://jasssbo.github.io/GoHackMe/privacy.html',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  height: 1.6,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    '[ACKNOWLEDGE]',
                    style: TextStyle(
                      color: CyberpunkColors.green,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
