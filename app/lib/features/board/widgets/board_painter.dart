import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_engine/go_engine.dart';

import '../../../core/theme/cyberpunk_colors.dart';

// ── Shared 3-D projection helpers ─────────────────────────────────────────

/// Computes screen pixels per world unit for the given view parameters.
///
/// Board cells are 1 world unit apart.  [elevation] is the angle from
/// horizontal (radians) and [zoom] is a linear scale multiplier.
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

/// Inverse-projects a 2-D screen [tap] onto the board surface plane
/// (world y = 0) and returns the nearest [Position], or null when outside.
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

  // Invert the orthographic projection at y = 0.
  final rx = (tap.dx - size.width  / 2) / s;
  final rz = (tap.dy - size.height / 2) / (s * sinEl);

  // Invert azimuth rotation (transpose of the rotation matrix).
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

// ── BoardPainter ────────────────────────────────────────────────────────────

/// Renders the Go board as a true 3-D slab using an orthographic axonometric
/// projection that can be freely rotated and zoomed by the parent widget.
///
/// The playing surface lies in the world y = 0 plane.  Board column [bx]
/// maps to world +X and board row [by] maps to world +Z.  The camera sits
/// above the board, parameterised by [azimuth] (rotation around the world Y
/// axis) and [elevation] (tilt angle from horizontal).
///
/// Star points pulse slowly via [starPulse] (0.0–1.0).
class BoardPainter extends CustomPainter {
  final Board     board;
  final int       boardSize;
  final Position? lastPlaced;
  final double    starPulse;

  /// Horizontal view rotation in radians.  Default π/4 = classic isometric.
  final double azimuth;

  /// Camera elevation above the horizontal plane in radians.
  /// Default ≈ arcsin(0.52) ≈ 31° reproduces the original cellH/cellW ratio.
  final double elevation;

  /// Linear zoom multiplier (1.0 = default fit).
  final double zoom;

  static const _stoneColors = {
    StoneColor.p1: CyberpunkColors.stoneP1,
    StoneColor.p2: CyberpunkColors.stoneP2,
    StoneColor.p3: CyberpunkColors.stoneP3,
    StoneColor.p4: CyberpunkColors.stoneP4,
  };

  BoardPainter({
    required this.board,
    required this.boardSize,
    this.lastPlaced,
    this.starPulse = 0.5,
    this.azimuth   = math.pi / 4,
    this.elevation = 0.546, // ≈ arcsin(0.52)
    this.zoom      = 1.0,
  });

  // ── Per-paint cached values ──────────────────────────────────────────────
  var _cosAz   = 0.0;
  var _sinAz   = 0.0;
  var _cosEl   = 0.0;
  var _sinEl   = 0.0;
  var _s       = 0.0; // pixels per world unit
  var _cx      = 0.0; // screen horizontal centre
  var _cy      = 0.0; // screen vertical centre
  var _boardCx = 0.0; // (boardSize-1)/2

  // ── Orthographic axonometric projection ─────────────────────────────────

  /// Projects board coordinate ([bx], [by]) at world height [y] to screen.
  ///
  ///   screenX = cx  +  (wx·cosAz − wz·sinAz) · s
  ///   screenY = cy  +  (wx·sinAz + wz·cosAz) · sinEl · s  −  y · cosEl · s
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

  // ── Path helper ──────────────────────────────────────────────────────────

  Path _quad(Offset a, Offset b, Offset c, Offset d) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..lineTo(d.dx, d.dy)
    ..close();

  // ── Paint entry point ────────────────────────────────────────────────────

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
    _drawCoordLabels(canvas);
    _drawStones(canvas);
  }

  // ── Background ──────────────────────────────────────────────────────────

  void _drawBackground(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = CyberpunkColors.boardBackground,
    );
  }

  // ── Board slab ──────────────────────────────────────────────────────────

  static const _thickness = 0.40;

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

    // Outward-normal rz: positive = face visible (points toward camera).
    final faces = [
      (pts: [t00, t10, b10, b00], rz: -_cosAz), // North
      (pts: [t10, t11, b11, b10], rz:  _sinAz), // East
      (pts: [t11, t01, b01, b11], rz:  _cosAz), // South
      (pts: [t01, t00, b00, b01], rz: -_sinAz), // West
    ]..sort((a, b) => a.rz.compareTo(b.rz));

    for (final f in faces) {
      if (f.rz <= 0) {
        _drawSideFace(canvas, f.pts[0], f.pts[1], f.pts[2], f.pts[3],
            hidden: true);
      }
    }

    _drawBoardTopSurface(canvas, size, t00, t10, t11, t01);
    _drawGrid(canvas);
    _drawStarPoints(canvas);

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
    canvas.drawPath(
        path, Paint()..color = const Color(0xFF07121C)..style = PaintingStyle.fill);
    canvas.save();
    canvas.clipPath(path);
    final dp   = Paint()..color = CyberpunkColors.cyan.withValues(alpha: 0.022);
    final step = _s * 1.35;
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 0.7, dp);
      }
    }
    canvas.restore();
  }

  void _drawSideFace(
    Canvas canvas, Offset a, Offset b, Offset c, Offset d, {
    required bool hidden,
    double rz = 0,
  }) {
    canvas.drawPath(
      _quad(a, b, c, d),
      Paint()
        ..color = const Color(0xFF040C13)
            .withValues(alpha: hidden ? 0.70 : 0.94)
        ..style = PaintingStyle.fill,
    );
    if (!hidden) {
      final edgeAlpha = (0.12 + rz.clamp(0.0, 1.0) * 0.38).clamp(0.05, 0.50);
      final ep = Paint()
        ..color = CyberpunkColors.cyanDim.withValues(alpha: edgeAlpha)
        ..strokeWidth = 0.85
        ..style = PaintingStyle.stroke;
      canvas.drawLine(a, d, ep);
      canvas.drawLine(b, c, ep);
      canvas.drawLine(d, c, ep);
    }
  }

  // ── Grid ────────────────────────────────────────────────────────────────

  void _drawGrid(Canvas canvas) {
    final n  = boardSize;
    final n1 = n - 1.0;
    final dim = Paint()
      ..color = const Color(0xFF1A3A55)
      ..strokeWidth = 0.55
      ..style = PaintingStyle.stroke;
    final edge = Paint()
      ..color = CyberpunkColors.cyanDim.withValues(alpha: 0.55)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    for (int y = 0; y < n; y++) {
      canvas.drawLine(
        _proj(0,  y.toDouble(), 0),
        _proj(n1, y.toDouble(), 0),
        (y == 0 || y == n - 1) ? edge : dim,
      );
    }
    for (int x = 0; x < n; x++) {
      canvas.drawLine(
        _proj(x.toDouble(), 0,  0),
        _proj(x.toDouble(), n1, 0),
        (x == 0 || x == n - 1) ? edge : dim,
      );
    }
  }

  // ── Coordinate labels ────────────────────────────────────────────────────

  void _drawCoordLabels(Canvas canvas) {
    final n  = boardSize;
    final n1 = n - 1.0;
    final fs = (_s * 0.30).clamp(5.5, 9.5);
    final style = TextStyle(
      color: CyberpunkColors.cyanDim.withValues(alpha: 0.40),
      fontSize: fs,
      fontFamily: 'monospace',
    );
    for (int i = 0; i < n; i++) {
      final lp = _proj(-0.80, i.toDouble(), 0);
      _label(canvas, String.fromCharCode(65 + i),
          lp + Offset(-fs * 0.5, -fs * 0.5), style);
      final rp = _proj(n1 + 0.50, i.toDouble(), 0);
      _label(canvas, '${i + 1}', rp + Offset(0, -fs * 0.5), style);
    }
  }

  void _label(Canvas canvas, String text, Offset offset, TextStyle style) {
    (TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout())
        .paint(canvas, offset);
  }

  // ── Star points ──────────────────────────────────────────────────────────

  void _drawStarPoints(Canvas canvas) {
    for (final pos in _starPositions()) {
      final c = _proj(pos.x.toDouble(), pos.y.toDouble(), 0);

      canvas.drawCircle(
        c,
        _s * 0.30 * (0.35 + starPulse * 0.65),
        Paint()
          ..color =
              CyberpunkColors.green.withValues(alpha: 0.07 + starPulse * 0.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );

      final r = _s * (0.09 + starPulse * 0.05);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - r)
          ..lineTo(c.dx + r * 0.58, c.dy)
          ..lineTo(c.dx, c.dy + r)
          ..lineTo(c.dx - r * 0.58, c.dy)
          ..close(),
        Paint()
          ..color =
              CyberpunkColors.green.withValues(alpha: 0.28 + starPulse * 0.45)
          ..style = PaintingStyle.fill,
      );
    }
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

  // ── Stones ───────────────────────────────────────────────────────────────

  void _drawStones(Canvas canvas) {
    if (board.stones.isEmpty) return;
    // Painter's algorithm: sort back-to-front by rz (ascending = back first).
    final sorted = board.stones.entries.toList()
      ..sort((a, b) {
        double rz(Position p) =>
            (p.x - _boardCx) * _sinAz + (p.y - _boardCx) * _cosAz;
        return rz(a.key).compareTo(rz(b.key));
      });
    for (final e in sorted) {
      _drawStone(canvas, e.key, e.value, e.key == lastPlaced);
    }
  }

  void _drawStone(Canvas canvas, Position pos, StoneColor sc, bool isLast) {
    final bx    = pos.x.toDouble();
    final by    = pos.y.toDouble();
    const r     = 0.42; // diamond radius in board units
    const h     = 0.18; // stone height in board units
    final color = _stoneColors[sc]!;

    final nS = _proj(bx,     by - r, 0);
    final eS = _proj(bx + r, by,     0);
    final sS = _proj(bx,     by + r, 0);
    final wS = _proj(bx - r, by,     0);

    final nH = _proj(bx,     by - r, h);
    final eH = _proj(bx + r, by,     h);
    final sH = _proj(bx,     by + r, h);
    final wH = _proj(bx - r, by,     h);

    final cH = _proj(bx, by, h);

    // Outer glow.
    canvas.drawOval(
      Rect.fromCenter(center: cH, width: r * 3.0 * _s, height: r * 2.0 * _s),
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * _s * 0.45),
    );

    // Four side faces — sorted back-to-front by face-centre rz.
    double fRz(double fbx, double fby) =>
        (fbx - _boardCx) * _sinAz + (fby - _boardCx) * _cosAz;

    final faceDefs = [
      (rz: fRz(bx - r / 2, by - r / 2), a: nH, b: wH, c: wS, d: nS, al: 0.24),
      (rz: fRz(bx + r / 2, by - r / 2), a: eH, b: nH, c: nS, d: eS, al: 0.20),
      (rz: fRz(bx - r / 2, by + r / 2), a: wH, b: sH, c: sS, d: wS, al: 0.20),
      (rz: fRz(bx + r / 2, by + r / 2), a: sH, b: eH, c: eS, d: sS, al: 0.30),
    ]..sort((a, b) => a.rz.compareTo(b.rz));

    for (final f in faceDefs) {
      canvas.drawPath(
        _quad(f.a, f.b, f.c, f.d),
        Paint()
          ..color = color.withValues(alpha: f.al)
          ..style = PaintingStyle.fill,
      );
    }

    // Top face diamond.
    final topPath = _quad(nH, eH, sH, wH);
    canvas.drawPath(topPath,
        Paint()..color = CyberpunkColors.boardBackground..style = PaintingStyle.fill);
    canvas.drawPath(topPath,
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 0.9);

    canvas.drawCircle(
        cH, r * _s * 0.18, Paint()..color = color.withValues(alpha: 0.95));

    if (isLast) {
      canvas.drawPath(
        topPath,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.36)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      canvas.drawCircle(
          cH, r * _s * 0.11, Paint()..color = Colors.white.withValues(alpha: 0.7));
    }
  }

  @override
  bool shouldRepaint(BoardPainter old) =>
      old.board      != board      ||
      old.lastPlaced != lastPlaced ||
      old.starPulse  != starPulse  ||
      old.azimuth    != azimuth    ||
      old.elevation  != elevation  ||
      old.zoom       != zoom;
}
