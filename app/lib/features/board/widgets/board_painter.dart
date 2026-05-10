import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_engine/go_engine.dart';

import '../../../core/theme/cyberpunk_colors.dart';

// ── Isometric helpers ──────────────────────────────────────────────────────

/// Computes the isometric cell half-widths that fit [size] for [boardSize].
({double cellW, double cellH}) isoCellDims(Size size, int boardSize) {
  final n = (boardSize - 1).toDouble();
  final cw = size.width * 0.46 / n;
  final ch = size.height * 0.42 / n;
  final cellW = math.min(cw, ch / 0.52);
  return (cellW: cellW, cellH: cellW * 0.52);
}

// ── BoardPainter ───────────────────────────────────────────────────────────

/// Renders the Go board as an isometric 3-D net with neon-glitch stones.
class BoardPainter extends CustomPainter {
  final Board board;
  final int boardSize;
  final Position? lastPlaced;

  /// 0.0–1.0 driven by an external animation for the star-point glow pulse.
  final double starPulse;

  static const _stoneColors = {
    StoneColor.p1: CyberpunkColors.stoneP1,
    StoneColor.p2: CyberpunkColors.stoneP2,
    StoneColor.p3: CyberpunkColors.stoneP3,
    StoneColor.p4: CyberpunkColors.stoneP4,
  };

  const BoardPainter({
    required this.board,
    required this.boardSize,
    this.lastPlaced,
    this.starPulse = 0.5,
  });

  // ── Projection ─────────────────────────────────────────────────────────

  Offset _iso(double bx, double by, Size size) {
    final (:cellW, :cellH) = isoCellDims(size, boardSize);
    final cx = (boardSize - 1) / 2.0;
    final originY = size.height * 0.10 + (boardSize - 1) * cellH;
    return Offset(
      size.width / 2.0 + (bx - cx - (by - cx)) * cellW,
      originY + ((bx - cx) + (by - cx)) * cellH,
    );
  }

  // ── Paint ───────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final dims = isoCellDims(size, boardSize);
    _drawBackground(canvas, size, dims.cellW);
    _drawGrid(canvas, size, dims.cellW, dims.cellH);
    _drawCoordLabels(canvas, size, dims.cellW, dims.cellH);
    _drawStarPoints(canvas, size, dims.cellW);
    _drawStones(canvas, size, dims.cellW, dims.cellH);
  }

  // ── Background ──────────────────────────────────────────────────────────

  void _drawBackground(Canvas canvas, Size size, double cellW) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = CyberpunkColors.boardBackground,
    );
    final tl = _iso(0, 0, size);
    final tr = _iso(boardSize - 1.0, 0, size);
    final br = _iso(boardSize - 1.0, boardSize - 1.0, size);
    final bl = _iso(0, boardSize - 1.0, size);
    canvas.drawPath(
      Path()
        ..moveTo(tl.dx, tl.dy)
        ..lineTo(tr.dx, tr.dy)
        ..lineTo(br.dx, br.dy)
        ..lineTo(bl.dx, bl.dy)
        ..close(),
      Paint()..color = const Color(0xFF07121C),
    );
    // Subtle noise dots watermark
    final dotPaint = Paint()
      ..color = CyberpunkColors.cyan.withValues(alpha: 0.022);
    final spacing = cellW * 1.4;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 0.7, dotPaint);
      }
    }
  }

  // ── Grid ────────────────────────────────────────────────────────────────

  void _drawGrid(Canvas canvas, Size size, double cellW, double cellH) {
    final n = boardSize;
    final n1 = n - 1.0;

    final dimPaint = Paint()
      ..color = const Color(0xFF1A3A55)
      ..strokeWidth = 0.55
      ..style = PaintingStyle.stroke;
    final edgePaint = Paint()
      ..color = CyberpunkColors.cyanDim.withValues(alpha: 0.55)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    for (int y = 0; y < n; y++) {
      canvas.drawLine(
        _iso(0, y.toDouble(), size),
        _iso(n1, y.toDouble(), size),
        (y == 0 || y == n - 1) ? edgePaint : dimPaint,
      );
    }
    for (int x = 0; x < n; x++) {
      canvas.drawLine(
        _iso(x.toDouble(), 0, size),
        _iso(x.toDouble(), n1, size),
        (x == 0 || x == n - 1) ? edgePaint : dimPaint,
      );
    }

    // Depth drop lines at every node — the 3-D net illusion
    const dropLen = 3.5;
    final dropPaint = Paint()
      ..color = CyberpunkColors.cyanDim.withValues(alpha: 0.20)
      ..strokeWidth = 0.5;
    for (int x = 0; x < n; x++) {
      for (int y = 0; y < n; y++) {
        final p = _iso(x.toDouble(), y.toDouble(), size);
        canvas.drawLine(p, p + const Offset(0, dropLen), dropPaint);
      }
    }

    // Bottom depth face (floor edge of the net)
    final bl = _iso(0, n1, size);
    final br = _iso(n1, n1, size);
    final tr = _iso(n1, 0, size);
    const d = 6.0;
    final facePaint = Paint()
      ..color = const Color(0xFF0A1E30)
      ..style = PaintingStyle.fill;
    canvas.drawPath(
      Path()
        ..moveTo(bl.dx, bl.dy)
        ..lineTo(br.dx, br.dy)
        ..lineTo(br.dx, br.dy + d)
        ..lineTo(bl.dx, bl.dy + d)
        ..close(),
      facePaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(br.dx, br.dy)
        ..lineTo(tr.dx, tr.dy)
        ..lineTo(tr.dx, tr.dy + d)
        ..lineTo(br.dx, br.dy + d)
        ..close(),
      facePaint,
    );
    final edgeLine = Paint()
      ..color = CyberpunkColors.cyanDim.withValues(alpha: 0.18)
      ..strokeWidth = 0.7;
    canvas.drawLine(bl, bl + const Offset(0, d), edgeLine);
    canvas.drawLine(br, br + const Offset(0, d), edgeLine);
    canvas.drawLine(tr, tr + const Offset(0, d), edgeLine);
    canvas.drawLine(
      bl + const Offset(0, d), br + const Offset(0, d), edgeLine);
    canvas.drawLine(
      br + const Offset(0, d), tr + const Offset(0, d), edgeLine);
  }

  // ── Coordinate labels ────────────────────────────────────────────────────

  void _drawCoordLabels(
      Canvas canvas, Size size, double cellW, double cellH) {
    final n = boardSize;
    final fontSize = (cellW * 0.44).clamp(5.5, 9.5);
    final style = TextStyle(
      color: CyberpunkColors.cyanDim.withValues(alpha: 0.40),
      fontSize: fontSize,
      fontFamily: 'monospace',
    );
    for (int i = 0; i < n; i++) {
      // Letters on the left edge (top axis)
      final lp = _iso(0, i.toDouble(), size);
      _label(canvas, String.fromCharCode(65 + i),
          lp + Offset(-cellW * 0.9, -fontSize / 2), style);
      // Numbers on the right edge (side axis)
      final rp = _iso(n - 1.0, i.toDouble(), size);
      _label(canvas, '${i + 1}',
          rp + Offset(cellW * 0.28, -fontSize / 2), style);
    }
  }

  void _label(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  // ── Star points ──────────────────────────────────────────────────────────

  void _drawStarPoints(Canvas canvas, Size size, double cellW) {
    for (final pos in _starPositions()) {
      final c = _iso(pos.x.toDouble(), pos.y.toDouble(), size);

      // Pulsing glow halo (PCB network node)
      canvas.drawCircle(
        c,
        cellW * 0.32 * (0.35 + starPulse * 0.65),
        Paint()
          ..color =
              CyberpunkColors.green.withValues(alpha: 0.07 + starPulse * 0.10)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );

      // Diamond dot — size and brightness pulse with the animation
      final s = cellW * (0.09 + starPulse * 0.05);
      final paint = Paint()
        ..color =
            CyberpunkColors.green.withValues(alpha: 0.28 + starPulse * 0.45)
        ..style = PaintingStyle.fill;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - s)
          ..lineTo(c.dx + s * 0.58, c.dy)
          ..lineTo(c.dx, c.dy + s)
          ..lineTo(c.dx - s * 0.58, c.dy)
          ..close(),
        paint,
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
      return [
        const Position(2, 2), const Position(6, 2),
        const Position(4, 4),
        const Position(2, 6), const Position(6, 6),
      ];
    }
    return const [];
  }

  // ── Stones ───────────────────────────────────────────────────────────────

  void _drawStones(Canvas canvas, Size size, double cellW, double cellH) {
    for (final entry in board.stones.entries) {
      _drawStone(canvas, size, entry.key, entry.value,
          entry.key == lastPlaced, cellW, cellH);
    }
  }

  void _drawStone(
    Canvas canvas,
    Size size,
    Position pos,
    StoneColor sc,
    bool isLast,
    double cellW,
    double cellH,
  ) {
    final c = _iso(pos.x.toDouble(), pos.y.toDouble(), size);
    final color = _stoneColors[sc]!;
    final rw = cellW * 0.50;
    final rh = cellH * 0.50;
    const depth = 4.5;

    // Outer glow
    canvas.drawOval(
      Rect.fromCenter(center: c, width: rw * 3.0, height: rh * 2.2),
      Paint()
        ..color = color.withValues(alpha: 0.20)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cellW * 0.55),
    );

    // Left face
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - rw, c.dy)
        ..lineTo(c.dx, c.dy + rh)
        ..lineTo(c.dx, c.dy + rh + depth)
        ..lineTo(c.dx - rw, c.dy + depth)
        ..close(),
      Paint()
        ..color = color.withValues(alpha: 0.16)
        ..style = PaintingStyle.fill,
    );

    // Right face
    canvas.drawPath(
      Path()
        ..moveTo(c.dx + rw, c.dy)
        ..lineTo(c.dx, c.dy + rh)
        ..lineTo(c.dx, c.dy + rh + depth)
        ..lineTo(c.dx + rw, c.dy + depth)
        ..close(),
      Paint()
        ..color = color.withValues(alpha: 0.26)
        ..style = PaintingStyle.fill,
    );

    // Top face (isometric diamond)
    final top = Path()
      ..moveTo(c.dx, c.dy - rh)
      ..lineTo(c.dx + rw, c.dy)
      ..lineTo(c.dx, c.dy + rh)
      ..lineTo(c.dx - rw, c.dy)
      ..close();
    canvas.drawPath(
      top,
      Paint()
        ..color = CyberpunkColors.boardBackground
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      top,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );

    // Center glyph
    canvas.drawCircle(
        c, rw * 0.20, Paint()..color = color.withValues(alpha: 0.95));

    // Last-move flash
    if (isLast) {
      canvas.drawPath(
        top,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.36)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      canvas.drawCircle(
          c, rw * 0.11, Paint()..color = Colors.white.withValues(alpha: 0.7));
    }
  }

  @override
  bool shouldRepaint(BoardPainter old) =>
      old.board != board ||
      old.lastPlaced != lastPlaced ||
      old.starPulse != starPulse;
}
