import 'package:flutter/material.dart';
import 'package:go_engine/go_engine.dart';

import 'board_painter.dart';

/// Interactive Go board widget using the isometric [BoardPainter].
///
/// Hit-testing uses the inverse of the isometric projection so that taps
/// land on the correct intersection even on the tilted net.
///
/// Star points pulse slowly (Lain NAVI network-node feel) via an internal
/// [AnimationController] — no external animation management needed.
class BoardWidget extends StatefulWidget {
  final Board board;
  final int boardSize;
  final Position? lastPlaced;
  final void Function(Position pos)? onTap;

  const BoardWidget({
    super.key,
    required this.board,
    required this.boardSize,
    this.lastPlaced,
    this.onTap,
  });

  @override
  State<BoardWidget> createState() => _BoardWidgetState();

  /// Inverse isometric hit-test shared with the state.
  static Position? isoHitTest(Offset tap, Size size, int boardSize) {
    final (:cellW, :cellH) = isoCellDims(size, boardSize);
    final cx = (boardSize - 1) / 2.0;
    final originY = size.height * 0.10 + (boardSize - 1) * cellH;

    final tx = tap.dx - size.width / 2.0;
    final ty = tap.dy - originY;

    final uMinV = tx / cellW;
    final uPlusV = ty / cellH;

    final u = (uMinV + uPlusV) / 2.0;
    final v = (uPlusV - uMinV) / 2.0;

    final bxf = u + cx;
    final byf = v + cx;
    final bx = bxf.round();
    final by = byf.round();

    if (bx < 0 || bx >= boardSize || by < 0 || by >= boardSize) return null;
    if ((bxf - bx).abs() > 0.42 || (byf - by).abs() > 0.42) return null;

    return Position(bx, by);
  }
}

class _BoardWidgetState extends State<BoardWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : w;
        final canvasSize = Size(w, h);

        return GestureDetector(
          onTapDown: widget.onTap == null
              ? null
              : (details) {
                  final pos = BoardWidget.isoHitTest(
                    details.localPosition,
                    canvasSize,
                    widget.boardSize,
                  );
                  if (pos != null) widget.onTap!(pos);
                },
          child: AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => RepaintBoundary(
              child: CustomPaint(
                size: canvasSize,
                painter: BoardPainter(
                  board: widget.board,
                  boardSize: widget.boardSize,
                  lastPlaced: widget.lastPlaced,
                  starPulse: _pulseCtrl.value,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}