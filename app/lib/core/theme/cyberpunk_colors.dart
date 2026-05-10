import 'package:flutter/material.dart';

/// GoHackMe cyberpunk colour palette.
///
/// Inspired by 90s hacker films: dark backgrounds, neon glows, phosphor screens.
class CyberpunkColors {
  CyberpunkColors._();

  // ── Background hierarchy ──────────────────────────────────────────────────
  static const background = Color(0xFF050A0F); // near-black blue-tinted
  static const surface = Color(0xFF0A1520); // panel/card background
  static const surfaceAlt = Color(0xFF0D1B2A); // slightly lighter panel
  static const wiredIndigo = Color(0xFF150828); // The Wired — deep protocol space

  // ── Primary neon accents ──────────────────────────────────────────────────
  static const cyan = Color(0xFF00F5FF); // primary UI cyan
  static const cyanDim = Color(0xFF00A8B0); // dimmed cyan for borders
  static const magenta = Color(0xFFFF00FF); // P2 colour / highlight
  static const green = Color(0xFF39FF14); // terminal green / P3
  static const orange = Color(0xFFFF6A00); // P4 / warning
  static const yellow = Color(0xFFFFE600); // subnet / resource colour

  // ── Stone colours (each player) ──────────────────────────────────────────
  static const stoneP1 = cyan; // Player 1
  static const stoneP2 = magenta; // Player 2
  static const stoneP3 = green; // Player 3
  static const stoneP4 = orange; // Player 4

  // ── Board colours ─────────────────────────────────────────────────────────
  static const boardGrid = Color(0xFF1A3044); // grid lines
  static const boardBackground = Color(0xFF060D14); // board surface
  static const starPoint = Color(0xFF2A5070); // star point dots

  // ── Status / feedback ─────────────────────────────────────────────────────
  static const success = Color(0xFF39FF14);
  static const error = Color(0xFFFF2D55);
  static const warning = yellow;
  static const info = cyan;

  // ── Text ──────────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFE0F7FA); // near-white
  static const textSecondary = Color(0xFF80DEEA); // muted cyan
  static const textDim = Color(0xFF37474F); // very muted

  // ── Glow helpers ──────────────────────────────────────────────────────────

  /// Returns a [BoxShadow] list that simulates a neon glow for [color].
  static List<BoxShadow> glowFor(Color color, {double intensity = 1.0}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.6 * intensity),
          blurRadius: 8 * intensity,
          spreadRadius: 1 * intensity,
        ),
        BoxShadow(
          color: color.withValues(alpha: 0.3 * intensity),
          blurRadius: 20 * intensity,
          spreadRadius: 4 * intensity,
        ),
      ];
}
