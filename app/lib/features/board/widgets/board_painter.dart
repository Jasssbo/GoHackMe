import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_engine/go_engine.dart';

import '../../../core/theme/cyberpunk_colors.dart';

// ── Shared 3-D projection helpers ──────────────────────────────────────────

double compute3dScale(
    Size size, int boardSize, double elevation, double zoom) {
  final n = (boardSize - 1).toDouble();
  if (n <= 0) return zoom;
  final diag  = n * math.sqrt2;
  final sinEl = math.sin(elevation).clamp(0.1, 1.0);
  final sx    = size.width  * 0.82 / diag;
  final sy    = size.height * 0.82 / (diag * sinEl);
  return zoom * math.min(sx, sy);
}

Position? board3dHitTest(
  Offset tap,
  Size   size,
  int    boardSize,
  double azimuth,
  double elevation,
  double zoom,
) {
  final s     = compute3dScale(size, boardSize, elevation, zoom);
  final sinEl = math.sin(elevation).clamp(0.1, 1.0);
  final cosAz = math.cos(azimuth);
  final sinAz = math.sin(azimuth);
  final cx    = (boardSize - 1) / 2.0;

  final rx = (tap.dx - size.width  / 2) / s;
  final rz = (tap.dy - size.height / 2) / (s * sinEl);

  final wx = rx * cosAz + rz * sinAz;
  final wz = -rx * sinAz + rz * cosAz;

  final bxf = wx + cx;
  final byf = wz + cx;
  final bx  = bxf.round();
  final by  = byf.round();

  if (bx < 0 || bx >= boardSize || by < 0 || by >= boardSize) return null;
  if ((bxf - bx).abs() > 0.5 || (byf - by).abs() > 0.5) return null;
  return Position(bx, by);
}

// ── Signal identity per player (waveform, color, node shape index) ─────────

class _SignalIdentity {
  final Color  baseColor;
  final Color  dimColor;
  final int    nodeShape;   // 0=diamond, 1=hex, 2=cross, 3=square
  final double glowRadius;

  const _SignalIdentity({
    required this.baseColor,
    required this.dimColor,
    required this.nodeShape,
    required this.glowRadius,
  });
}

const _signalIdentities = {
  StoneColor.p1: _SignalIdentity(
    baseColor: CyberpunkColors.signalP1,
    dimColor:  Color(0xFF0D3A42),
    nodeShape: 0,
    glowRadius: 0.40,
  ),
  StoneColor.p2: _SignalIdentity(
    baseColor: CyberpunkColors.signalP2,
    dimColor:  Color(0xFF1E3040),
    nodeShape: 1,
    glowRadius: 0.55,
  ),
  StoneColor.p3: _SignalIdentity(
    baseColor: CyberpunkColors.signalP3,
    dimColor:  Color(0xFF1A2C10),
    nodeShape: 2,
    glowRadius: 0.38,
  ),
  StoneColor.p4: _SignalIdentity(
    baseColor: CyberpunkColors.signalP4,
    dimColor:  Color(0xFF2A1808),
    nodeShape: 3,
    glowRadius: 0.42,
  ),
};

// ── BoardPainter ─────────────────────────────────────────────────────────────

class BoardPainter extends CustomPainter {
  final Board     board;
  final int       boardSize;
  final Position? lastPlaced;
  final double    starPulse;
  final double    packetPhase;
  final double    flickerAlpha;

  /// Stone color of the player whose turn it is.
  /// When non-null, that player's stones receive a subtle blink ring.
  final StoneColor? activePlayerColor;

  /// Value from the turn-blink AnimationController [0..1], reversed.
  final double activePulse;

  final double azimuth;
  final double elevation;
  final double zoom;

  /// When non-null (scoring/finished phase) each entry marks an empty
  /// intersection controlled by the given [StoneColor] as territory.
  final Map<Position, StoneColor>? scoringTerritory;

  BoardPainter({
    required this.board,
    required this.boardSize,
    this.lastPlaced,
    this.starPulse    = 0.5,
    this.packetPhase  = 0.0,
    this.flickerAlpha = 0.0,
    this.activePlayerColor,
    this.activePulse  = 0.5,
    this.azimuth   = math.pi / 4,
    this.elevation = 0.546,
    this.zoom      = 1.0,
    this.scoringTerritory,
  });

  var _cosAz   = 0.0;
  var _sinAz   = 0.0;
  var _cosEl   = 0.0;
  var _sinEl   = 0.0;
  var _s       = 0.0;
  var _cx      = 0.0;
  var _cy      = 0.0;
  var _boardCx = 0.0;

  final _rng = math.Random(42);

  // ── Pre-allocated reusable buffers for Optimization 2 ────────────────────
  final Path _quadPathBuffer = Path();
  final Path _hexPathBuffer = Path();
  final Path _squarePathBuffer = Path();
  final Path _tracePathBuffer = Path();
  final Path _diamondPathBuffer = Path();

  final Paint _bgPaint = Paint()..color = const Color(0xFF030506);
  final Paint _vignettePaint = Paint();
  static Shader? _cachedVignetteShader;
  static Size _cachedVignetteSize = Size.zero;

  Offset _proj(double bx, double by, double y) {
    final wx = bx - _boardCx;
    final wz = by - _boardCx;
    final rx = wx * _cosAz - wz * _sinAz;
    final rz = wx * _sinAz + wz * _cosAz;
    return Offset(
      _cx + rx * _s,
      _cy + rz * _sinEl * _s - y * _cosEl * _s,
    );
  }

  Path _quad(Offset a, Offset b, Offset c, Offset d) {
    _quadPathBuffer.reset();
    _quadPathBuffer.moveTo(a.dx, a.dy);
    _quadPathBuffer.lineTo(b.dx, b.dy);
    _quadPathBuffer.lineTo(c.dx, c.dy);
    _quadPathBuffer.lineTo(d.dx, d.dy);
    _quadPathBuffer.close();
    return _quadPathBuffer;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _cosAz   = math.cos(azimuth);
    _sinAz   = math.sin(azimuth);
    _cosEl   = math.cos(elevation);
    _sinEl   = math.sin(elevation).clamp(0.1, 1.0);
    _s       = compute3dScale(size, boardSize, elevation, zoom);
    _cx      = size.width  / 2;
    _cy      = size.height / 2;
    _boardCx = (boardSize - 1) / 2.0;

    _drawBackground(canvas, size);
    _drawBoardSlab(canvas, size);
    _drawNodeConnections(canvas);   // same-player adjacency traces
    _drawScoringOverlay(canvas);
    _drawCoordLabels(canvas);
    _drawStones(canvas);
    _drawFlicker(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _bgPaint);
    if (_cachedVignetteShader == null || _cachedVignetteSize != size) {
      _cachedVignetteSize = size;
      _cachedVignetteShader = RadialGradient(
        center: Alignment.center,
        radius: 0.85,
        colors: [
          Colors.transparent,
          const Color(0xFF010203).withValues(alpha: 0.6),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    }
    _vignettePaint.shader = _cachedVignetteShader;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _vignettePaint);
  }

  static const _thickness = 0.30;

  void _drawBoardSlab(Canvas canvas, Size size) {
    final n1 = boardSize - 1.0;
    const t  = _thickness;

    final t00 = _proj(0,  0,  0);
    final t10 = _proj(n1, 0,  0);
    final t11 = _proj(n1, n1, 0);
    final t01 = _proj(0,  n1, 0);

    final b00 = _proj(0,  0,  -t);
    final b10 = _proj(n1, 0,  -t);
    final b11 = _proj(n1, n1, -t);
    final b01 = _proj(0,  n1, -t);

    final faces = [
      (pts: [t00, t10, b10, b00], rz: -_cosAz),
      (pts: [t10, t11, b11, b10], rz:  _sinAz),
      (pts: [t11, t01, b01, b11], rz:  _cosAz),
      (pts: [t01, t00, b00, b01], rz: -_sinAz),
    ]..sort((a, b) => a.rz.compareTo(b.rz));

    for (final f in faces) {
      if (f.rz <= 0) {
        _drawSideFace(canvas, f.pts[0], f.pts[1], f.pts[2], f.pts[3],
            hidden: true);
      }
    }

    _drawBoardTopSurface(canvas, size, t00, t10, t11, t01);
    _drawTerritoryZones(canvas);
    _drawTraces(canvas);
    _drawNetworkNodes(canvas);

    for (final f in faces.reversed) {
      if (f.rz > 0) {
        _drawSideFace(canvas, f.pts[0], f.pts[1], f.pts[2], f.pts[3],
            hidden: false, rz: f.rz);
      }
    }
  }

  void _drawBoardTopSurface(Canvas canvas, Size size,
      Offset t00, Offset t10, Offset t11, Offset t01) {
    final path = _quad(t00, t10, t11, t01);
    canvas.drawPath(path,
        Paint()..color = const Color(0xFF05080A)..style = PaintingStyle.fill);
    canvas.save();
    canvas.clipPath(path);
    final dp   = Paint()..color = const Color(0xFF0E1A15).withValues(alpha: 0.6);
    final step = _s * 0.55;
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        final stagger = ((x / step).floor() % 2 == 0) ? 0.0 : step * 0.5;
        canvas.drawCircle(Offset(x, y + stagger), 0.55, dp);
      }
    }
    canvas.restore();

    final activeColor = activePlayerColor != null
        ? _signalIdentities[activePlayerColor]!.baseColor
        : null;
    final strokeColor = activeColor != null
        ? activeColor.withValues(alpha: 0.35 + 0.55 * activePulse)
        : const Color(0xFF0E221C);
    final strokeWidth = activeColor != null ? 2.5 : 1.0;
    canvas.drawPath(
      path,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
    if (activeColor != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = activeColor.withValues(alpha: 0.18 * activePulse)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5,
      );
    }
  }

  void _drawSideFace(
    Canvas canvas, Offset a, Offset b, Offset c, Offset d, {
    required bool hidden,
    double rz = 0,
  }) {
    canvas.drawPath(
      _quad(a, b, c, d),
      Paint()
        ..color = const Color(0xFF030608)
            .withValues(alpha: hidden ? 0.85 : 0.96)
        ..style = PaintingStyle.fill,
    );
    if (!hidden) {
      final edgeAlpha = (0.06 + rz.clamp(0.0, 1.0) * 0.20).clamp(0.04, 0.28);
      final ep = Paint()
        ..color = CyberpunkColors.amberDim.withValues(alpha: edgeAlpha * 3)
        ..strokeWidth = 0.7
        ..style = PaintingStyle.stroke;
      canvas.drawLine(a, d, ep);
      canvas.drawLine(b, c, ep);
      canvas.drawLine(d, c, ep);
      final tp = Paint()
        ..color = CyberpunkColors.cyanDim.withValues(alpha: edgeAlpha * 1.5)
        ..strokeWidth = 0.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(a, b, tp);
    }
  }

  void _drawTerritoryZones(Canvas canvas) {
    if (board.stones.isEmpty) return;
    final byPlayer = <StoneColor, List<Position>>{};
    for (final e in board.stones.entries) {
      byPlayer.putIfAbsent(e.value, () => []).add(e.key);
    }
    for (final entry in byPlayer.entries) {
      final identity = _signalIdentities[entry.key];
      if (identity == null) continue;
      final color = identity.baseColor;
      final isActive = entry.key == activePlayerColor;
      final pVal = isActive ? activePulse : 0.0;
      for (final pos in entry.value) {
        final c = _proj(pos.x.toDouble(), pos.y.toDouble(), 0.005);
        // Organic radius: deterministic seed from position so halos are uneven
        final seed = (pos.x * 13 + pos.y * 7) % 100 / 100.0;
        final baseR = 0.78 + seed * 0.22;
        final radius = _s * (baseR + pVal * 0.16);
        // Slightly non-uniform aspect ratio per stone for blob feel
        final aspectSeed = (pos.x * 7 + pos.y * 19) % 100 / 100.0;
        final wMul = 1.50 + aspectSeed * 0.20;
        final hMul = 0.84 + aspectSeed * 0.14;
        final baseAlpha = isActive ? 0.035 + pVal * 0.035 : 0.020;
        canvas.drawOval(
          Rect.fromCenter(center: c, width: radius * wMul * 1.25, height: radius * hMul * 1.25),
          Paint()..color = color.withValues(alpha: baseAlpha * 0.4),
        );
        canvas.drawOval(
          Rect.fromCenter(center: c, width: radius * wMul, height: radius * hMul),
          Paint()..color = color.withValues(alpha: baseAlpha),
        );
      }
    }
  }

  /// Draws organic bezier traces connecting adjacent stones of the same player.
  /// Called after the board slab is fully rendered but before stone bodies.
  void _drawNodeConnections(Canvas canvas) {
    if (board.stones.isEmpty) return;

    // Group stones by player
    final byColor = <StoneColor, Set<Position>>{};
    for (final e in board.stones.entries) {
      byColor.putIfAbsent(e.value, () => {}).add(e.key);
    }

    // Float at h just below stone tops so connections emerge between bodies
    const h = 0.18;

    for (final entry in byColor.entries) {
      final identity = _signalIdentities[entry.key];
      if (identity == null) continue;
      final color = identity.baseColor;
      final posSet = entry.value;
      final isActive = entry.key == activePlayerColor;
      final pVal = isActive ? activePulse : 0.0;

      for (final pos in posSet) {
        // Only check right (+x) and down (+y) to avoid drawing each edge twice
        for (final nb in [
          Position(pos.x + 1, pos.y),
          Position(pos.x, pos.y + 1),
        ]) {
          if (!posSet.contains(nb)) continue;

          final p0 = _proj(pos.x.toDouble(), pos.y.toDouble(), h);
          final p1 = _proj(nb.x.toDouble(), nb.y.toDouble(), h);

          final dx  = p1.dx - p0.dx;
          final dy  = p1.dy - p0.dy;
          final len = math.sqrt(dx * dx + dy * dy);
          if (len < 0.5) continue;

          // Deterministic bow per edge — seeds from both endpoint positions
          final bowSeed = ((pos.x * 31 + pos.y * 17 + nb.x * 11) % 100) / 100.0;
          final bowSign = bowSeed > 0.5 ? 1.0 : -1.0;
          // Perpendicular unit vector in screen space
          final pnx = -dy / len;
          final pny =  dx / len;
          final bowAmt = _s * (0.04 + bowSeed * 0.05) * bowSign;

          final ctrl = Offset(
            (p0.dx + p1.dx) / 2 + pnx * bowAmt,
            (p0.dy + p1.dy) / 2 + pny * bowAmt,
          );

          final path = _tracePathBuffer
            ..reset()
            ..moveTo(p0.dx, p0.dy)
            ..quadraticBezierTo(ctrl.dx, ctrl.dy, p1.dx, p1.dy);

          // Soft glow halo without offscreen blur
          canvas.drawPath(
            path,
            Paint()
              ..color = color.withValues(alpha: isActive ? 0.08 + pVal * 0.10 : 0.04)
              ..strokeWidth = _s * (isActive ? 0.26 : 0.16)
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round,
          );

          // Core trace
          canvas.drawPath(
            path,
            Paint()
              ..color = color.withValues(alpha: isActive ? 0.65 + pVal * 0.25 : 0.35)
              ..strokeWidth = isActive ? 1.4 : 0.9
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round,
          );

          // Bright inner spine
          canvas.drawPath(
            path,
            Paint()
              ..color = color.withValues(alpha: isActive ? 0.85 + pVal * 0.15 : 0.45)
              ..strokeWidth = 0.5
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }
  }

  void _drawTraces(Canvas canvas) {
    final n  = boardSize;
    final n1 = n - 1.0;
    final tracePaint = Paint()
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    final edgePaint = Paint()
      ..color = CyberpunkColors.cyanDim.withValues(alpha: 0.55)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    for (int y = 0; y < n; y++) {
      final isEdge = y == 0 || y == n - 1;
      if (isEdge) {
        canvas.drawLine(_proj(0, y.toDouble(), 0), _proj(n1, y.toDouble(), 0), edgePaint);
      } else {
        final seed = (y * 7 + 3) % 13;
        final alpha = 0.22 + (seed % 5) * 0.018;
        final decayAlpha = (y % 5 == 2) ? alpha * 0.5 : alpha;
        tracePaint.color = CyberpunkColors.cyanDim.withValues(alpha: decayAlpha);
        _drawImperfectLine(canvas, y.toDouble(), true, tracePaint, n1);
      }
    }
    for (int x = 0; x < n; x++) {
      final isEdge = x == 0 || x == n - 1;
      if (isEdge) {
        canvas.drawLine(_proj(x.toDouble(), 0, 0), _proj(x.toDouble(), n1, 0), edgePaint);
      } else {
        final seed = (x * 11 + 7) % 17;
        final alpha = 0.22 + (seed % 5) * 0.018;
        final decayAlpha = (x % 7 == 4) ? alpha * 0.45 : alpha;
        tracePaint.color = CyberpunkColors.cyanDim.withValues(alpha: decayAlpha);
        _drawImperfectLine(canvas, x.toDouble(), false, tracePaint, n1);
      }
    }
  }

  void _drawImperfectLine(Canvas canvas, double idx, bool isRow,
      Paint paint, double n1) {
    const segs = 4;
    final step = n1 / segs;
    for (int s = 0; s < segs; s++) {
      final t0 = s * step;
      final t1 = (s + 1) * step;
      final jitter0 = (_rng.nextDouble() - 0.5) * 0.018;
      final jitter1 = (_rng.nextDouble() - 0.5) * 0.018;
      final Offset p0, p1;
      if (isRow) {
        p0 = _proj(t0, idx + jitter0, 0);
        p1 = _proj(t1, idx + jitter1, 0);
      } else {
        p0 = _proj(idx + jitter0, t0, 0);
        p1 = _proj(idx + jitter1, t1, 0);
      }
      canvas.drawLine(p0, p1, paint);
    }
  }

  void _drawNetworkNodes(Canvas canvas) {
    final n = boardSize;
    final starSet = _starPositions().toSet();
    final nodePaint = Paint()..style = PaintingStyle.fill;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (int x = 0; x < n; x++) {
      for (int y = 0; y < n; y++) {
        final pos = Position(x, y);
        final c = _proj(x.toDouble(), y.toDouble(), 0.008);
        if (starSet.contains(pos)) {
          _drawHubNode(canvas, c, nodePaint, ringPaint);
        } else {
          nodePaint.color = CyberpunkColors.cyanDim.withValues(alpha: 0.45);
          canvas.drawCircle(c, 1.1, nodePaint);
        }
      }
    }
  }

  void _drawHubNode(Canvas canvas, Offset c, Paint fill, Paint ring) {
    final pulseR = _s * 0.12 * (0.7 + starPulse * 0.3);
    final r      = _s * 0.060;
    fill.color = CyberpunkColors.green.withValues(alpha: 0.04 + starPulse * 0.04);
    canvas.drawCircle(c, pulseR * 2.2, fill);
    fill.color = CyberpunkColors.green.withValues(alpha: 0.08 + starPulse * 0.08);
    canvas.drawCircle(c, pulseR * 1.5, fill);
    ring.color = CyberpunkColors.greenDim.withValues(alpha: 0.45 + starPulse * 0.35);
    canvas.drawCircle(c, pulseR * 1.1, ring);
    fill.color = CyberpunkColors.green.withValues(alpha: 0.55 + starPulse * 0.40);
    canvas.drawCircle(c, r, fill);
  }

  void _drawCoordLabels(Canvas canvas) {
    final n  = boardSize;
    final n1 = n - 1.0;
    final fs = (_s * 0.28).clamp(5.0, 16.0);
    final style = TextStyle(
      color: CyberpunkColors.textDim.withValues(alpha: 0.55),
      fontSize: fs,
      fontFamily: 'monospace',
    );
    for (int i = 0; i < n; i++) {
      // Skip 'I' per standard Go convention (A-H then J-T).
      final charCode = i < 8 ? 65 + i : 66 + i;
      final lp = _proj(-0.80, i.toDouble(), 0);
      _label(canvas, String.fromCharCode(charCode),
          lp + Offset(-fs * 0.5, -fs * 0.5), style);
      final rp = _proj(n1 + 0.50, i.toDouble(), 0);
      _label(canvas, '${i + 1}', rp + Offset(0, -fs * 0.5), style);
    }
  }

  /// Draws small diamond markers on empty intersections that are claimed
  /// territory during the scoring/finished phase.
  void _drawScoringOverlay(Canvas canvas) {
    final territory = scoringTerritory;
    if (territory == null || territory.isEmpty) return;
    for (final entry in territory.entries) {
      final identity = _signalIdentities[entry.value];
      if (identity == null) continue;
      final c    = _proj(entry.key.x.toDouble(), entry.key.y.toDouble(), 0.012);
      final half = _s * 0.16;
      // Soft glow halo
      canvas.drawCircle(
        c,
        half * 2.2,
        Paint()..color = identity.baseColor.withValues(alpha: 0.06),
      );
      canvas.drawCircle(
        c,
        half * 1.4,
        Paint()..color = identity.baseColor.withValues(alpha: 0.12),
      );
      // Small diamond
      final path = _diamondPathBuffer
        ..reset()
        ..moveTo(c.dx,        c.dy - half)
        ..lineTo(c.dx + half * 0.7, c.dy)
        ..lineTo(c.dx,        c.dy + half)
        ..lineTo(c.dx - half * 0.7, c.dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = identity.baseColor.withValues(alpha: 0.70)
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _label(Canvas canvas, String text, Offset offset, TextStyle style) {
    (TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout())
        .paint(canvas, offset);
  }

  List<Position> _starPositions() {
    if (boardSize == 19) {
      const p = [3, 9, 15];
      return [for (final x in p) for (final y in p) Position(x, y)];
    }
    if (boardSize == 13) {
      const p = [3, 6, 9];
      return [for (final x in p) for (final y in p) Position(x, y)];
    }
    if (boardSize == 9) {
      return const [
        Position(2, 2), Position(6, 2),
        Position(4, 4),
        Position(2, 6), Position(6, 6),
      ];
    }
    return const [];
  }

  void _drawStones(Canvas canvas) {
    if (board.stones.isEmpty) return;
    final sorted = board.stones.entries.toList()
      ..sort((a, b) {
        double rz(Position p) =>
            (p.x - _boardCx) * _sinAz + (p.y - _boardCx) * _cosAz;
        return rz(a.key).compareTo(rz(b.key));
      });
    for (final e in sorted) {
      _drawNode(canvas, e.key, e.value, e.key == lastPlaced);
    }
  }

  void _drawNode(Canvas canvas, Position pos, StoneColor sc, bool isLast) {
    final identity = _signalIdentities[sc]!;
    final color    = identity.baseColor;
    final dimColor = identity.dimColor;
    final isActive = sc == activePlayerColor;
    final bx = pos.x.toDouble();
    final by = pos.y.toDouble();
    const r = 0.38;
    const h = 0.20;
    final cTop = _proj(bx, by, h);
    final cBot = _proj(bx, by, 0);

    // Coverage shadow (2 concentric ovals for soft falloff without blur)
    canvas.drawOval(
      Rect.fromCenter(center: cBot, width: r * 3.4 * _s, height: r * 1.9 * _s),
      Paint()..color = dimColor.withValues(alpha: 0.18),
    );
    canvas.drawOval(
      Rect.fromCenter(center: cBot, width: r * 2.8 * _s, height: r * 1.5 * _s),
      Paint()..color = dimColor.withValues(alpha: 0.35),
    );

    // Signal glow — ONLY active turn player's stones shine and pulse with light (soft shade glow)
    if (isActive) {
      final glowAlpha = 0.12 + activePulse * 0.20;
      canvas.drawOval(
        Rect.fromCenter(
            center: cTop,
            width: identity.glowRadius * 3.2 * _s,
            height: identity.glowRadius * 1.8 * _s),
        Paint()..color = color.withValues(alpha: glowAlpha * 0.4),
      );
      canvas.drawOval(
        Rect.fromCenter(
            center: cTop,
            width: identity.glowRadius * 2.2 * _s,
            height: identity.glowRadius * 1.3 * _s),
        Paint()..color = color.withValues(alpha: glowAlpha),
      );
    } else {
      // Non-active player stones get a subtle static non-pulsing background halo
      canvas.drawOval(
        Rect.fromCenter(
            center: cTop,
            width: identity.glowRadius * 2.0 * _s,
            height: identity.glowRadius * 1.2 * _s),
        Paint()..color = color.withValues(alpha: 0.05),
      );
    }

    final nS = _proj(bx,     by - r, 0);
    final eS = _proj(bx + r, by,     0);
    final sS = _proj(bx,     by + r, 0);
    final wS = _proj(bx - r, by,     0);
    final nH = _proj(bx,     by - r, h);
    final eH = _proj(bx + r, by,     h);
    final sH = _proj(bx,     by + r, h);
    final wH = _proj(bx - r, by,     h);

    double fRz(double fbx, double fby) =>
        (fbx - _boardCx) * _sinAz + (fby - _boardCx) * _cosAz;

    final faceDefs = [
      (rz: fRz(bx - r / 2, by - r / 2), a: nH, b: wH, c: wS, d: nS, al: isActive ? 0.32 : 0.20),
      (rz: fRz(bx + r / 2, by - r / 2), a: eH, b: nH, c: nS, d: eS, al: isActive ? 0.26 : 0.16),
      (rz: fRz(bx - r / 2, by + r / 2), a: wH, b: sH, c: sS, d: wS, al: isActive ? 0.26 : 0.16),
      (rz: fRz(bx + r / 2, by + r / 2), a: sH, b: eH, c: eS, d: sS, al: isActive ? 0.38 : 0.22),
    ]..sort((a, b) => a.rz.compareTo(b.rz));

    for (final f in faceDefs) {
      canvas.drawPath(
        _quad(f.a, f.b, f.c, f.d),
        Paint()
          ..color = color.withValues(alpha: f.al)
          ..style = PaintingStyle.fill,
      );
    }

    _drawNodeTopFace(canvas, sc, identity, bx, by, h, r, color, cTop, isLast,
        nH, eH, sH, wH, isActive);

    // Center node dot — active stone pulses brightly; non-active stone is static and dim
    final coreR = _s * 0.10 * (isActive ? (0.8 + activePulse * 0.3) : 0.7);
    final coreAlpha = isActive ? (0.80 + activePulse * 0.20) : 0.45;
    canvas.drawCircle(
        cTop,
        coreR,
        Paint()..color = color.withValues(alpha: coreAlpha));
  }

  void _drawNodeTopFace(
    Canvas canvas,
    StoneColor sc,
    _SignalIdentity identity,
    double bx, double by, double h, double r,
    Color color,
    Offset cTop,
    bool isLast,
    Offset nH, Offset eH, Offset sH, Offset wH,
    bool isActive,
  ) {
    final topPath = _quad(nH, eH, sH, wH);
    canvas.drawPath(topPath,
        Paint()..color = CyberpunkColors.boardBackground..style = PaintingStyle.fill);

    final strokeAlpha = isActive ? 0.90 : 0.45;
    switch (identity.nodeShape) {
      case 0: // Diamond — P1
        canvas.drawPath(topPath,
            Paint()
              ..color = color.withValues(alpha: strokeAlpha)
              ..style = PaintingStyle.stroke
              ..strokeWidth = isActive ? 1.0 : 0.7);
        break;
      case 1: // Hexagonal — P2
        final hex = _hexPath(cTop, _s * r * 0.82);
        canvas.drawPath(hex,
            Paint()
              ..color = color.withValues(alpha: strokeAlpha)
              ..style = PaintingStyle.stroke
              ..strokeWidth = isActive ? 0.9 : 0.6);
        break;
      case 2: // Cross terminal — P3
        _drawCrossTerminal(canvas, cTop, _s * r * 0.75, color.withValues(alpha: strokeAlpha));
        break;
      case 3: // Square — P4
        final sq = _squarePath(cTop, _s * r * 0.70);
        canvas.drawPath(sq,
            Paint()
              ..color = color.withValues(alpha: strokeAlpha)
              ..style = PaintingStyle.stroke
              ..strokeWidth = isActive ? 0.9 : 0.6);
        break;
    }

    if (isLast) {
      canvas.drawPath(
        topPath,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.20)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      canvas.drawCircle(cTop, _s * r * 0.12,
          Paint()..color = Colors.white.withValues(alpha: 0.55));
    }
  }

  Path _hexPath(Offset center, double radius) {
    _hexPathBuffer.reset();
    for (int i = 0; i < 6; i++) {
      final angle = math.pi / 6 + i * math.pi / 3;
      final p = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        _hexPathBuffer.moveTo(p.dx, p.dy);
      } else {
        _hexPathBuffer.lineTo(p.dx, p.dy);
      }
    }
    _hexPathBuffer.close();
    return _hexPathBuffer;
  }

  void _drawCrossTerminal(Canvas canvas, Offset c, double r, Color color) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.90)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), paint);
    canvas.drawLine(Offset(c.dx, c.dy - r * 0.6), Offset(c.dx, c.dy + r * 0.6), paint);
    paint.color = color.withValues(alpha: 0.55);
    paint.strokeWidth = 0.6;
    final t = r * 0.35;
    canvas.drawLine(Offset(c.dx - r, c.dy - t), Offset(c.dx - r, c.dy + t), paint);
    canvas.drawLine(Offset(c.dx + r, c.dy - t), Offset(c.dx + r, c.dy + t), paint);
  }

  Path _squarePath(Offset center, double half) {
    _squarePathBuffer.reset();
    _squarePathBuffer.addRect(Rect.fromCenter(center: center, width: half * 2, height: half * 1.4));
    return _squarePathBuffer;
  }

  void _drawFlicker(Canvas canvas, Size size) {
    if (flickerAlpha < 0.01) return;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black.withValues(alpha: flickerAlpha * 0.055),
    );
  }

  @override
  bool shouldRepaint(BoardPainter old) =>
      old.board        != board        ||
      old.lastPlaced   != lastPlaced   ||
      old.starPulse    != starPulse    ||
      old.packetPhase  != packetPhase  ||
      old.flickerAlpha != flickerAlpha ||
      old.azimuth      != azimuth      ||
      old.elevation    != elevation    ||
      old.zoom         != zoom;
}
