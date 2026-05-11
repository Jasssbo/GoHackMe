import 'package:flutter/material.dart';

/// GoHackMe colour palette — "The Wired" network infrastructure aesthetic.
///
/// Dark backgrounds with vivid CRT-green / cold cyan / amber accents.
/// Readable, saturated, atmospheric — still oppressive but not invisible.
class CyberpunkColors {
  CyberpunkColors._();

  // ── Background hierarchy ──────────────────────────────────────────────────
  static const background    = Color(0xFF060A0D); // near-black, slight teal tint
  static const surface       = Color(0xFF0B1018); // panel/card background
  static const surfaceAlt    = Color(0xFF101620); // slightly lighter panel
  static const wiredIndigo   = Color(0xFF080A14); // The Wired — protocol void

  // ── Primary accents ───────────────────────────────────────────────────────
  static const cyan          = Color(0xFF4DDADA); // bright cold teal
  static const cyanDim       = Color(0xFF2A9090); // mid teal for traces/labels
  static const green         = Color(0xFF3DBA50); // vivid phosphor green
  static const greenDim      = Color(0xFF1E6030); // dim phosphor
  static const amber         = Color(0xFFBB8830); // warm analog amber
  static const amberDim      = Color(0xFF604418); // dim amber

  // ── Legacy aliases ────────────────────────────────────────────────────────
  static const magenta = Color(0xFFB04880); // saturated mauve-pink
  static const yellow  = amber;
  static const orange  = signalP4;

  // ── Player signal identities ──────────────────────────────────────────────
  /// P1 — vivid cold teal
  static const signalP1      = Color(0xFF38C8D8);
  /// P2 — bright silver-blue
  static const signalP2      = Color(0xFF90B8D0);
  /// P3 — bright phosphor green
  static const signalP3      = Color(0xFF72B83C);
  /// P4 — warm copper-orange
  static const signalP4      = Color(0xFFCC7030);

  // ── Stone colour aliases ──────────────────────────────────────────────────
  static const stoneP1 = signalP1;
  static const stoneP2 = signalP2;
  static const stoneP3 = signalP3;
  static const stoneP4 = signalP4;

  // ── Board colours ─────────────────────────────────────────────────────────
  static const boardGrid       = Color(0xFF122820); // PCB trace tone
  static const boardBackground = Color(0xFF070C0A); // board void
  static const starPoint       = Color(0xFF205050); // node accent

  // ── Status / feedback ─────────────────────────────────────────────────────
  static const success  = Color(0xFF3DBA50);
  static const error    = Color(0xFFCC2840);
  static const warning  = amber;
  static const info     = cyan;

  // ── Text ──────────────────────────────────────────────────────────────────
  static const textPrimary   = Color(0xFFD0E4E4); // bright cold white
  static const textSecondary = Color(0xFF809898); // readable teal-gray
  static const textDim       = Color(0xFF405858); // visible but recessive

  // ── Glow helpers ──────────────────────────────────────────────────────────

  /// Returns a [BoxShadow] list that simulates a dim infrastructure glow.
  static List<BoxShadow> glowFor(Color color, {double intensity = 1.0}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.35 * intensity),
          blurRadius: 6 * intensity,
          spreadRadius: 0,
        ),
        BoxShadow(
          color: color.withValues(alpha: 0.15 * intensity),
          blurRadius: 16 * intensity,
          spreadRadius: 2 * intensity,
        ),
      ];
}
