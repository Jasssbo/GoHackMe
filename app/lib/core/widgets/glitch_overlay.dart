import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/cyberpunk_colors.dart';

// ── GlitchOverlay ─────────────────────────────────────────────────────────

/// Wraps [child] in a persistent CRT scanline layer and fires periodic
/// glitch-strip bursts (chromatic-aberration-style displaced bars).
///
/// Optionally accepts a [burstSignal] — increment its value to trigger an
/// immediate high-intensity burst (e.g. on attack).
class GlitchOverlay extends StatefulWidget {
  final Widget child;

  /// Incrementing this notifier fires an immediate burst.
  final ValueNotifier<int>? burstSignal;

  const GlitchOverlay({super.key, required this.child, this.burstSignal});

  @override
  State<GlitchOverlay> createState() => _GlitchOverlayState();
}

class _GlitchOverlayState extends State<GlitchOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  List<_Strip> _strips = const [];
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          if (mounted) setState(() => _strips = const []);
          _schedule();
        }
      });
    _schedule();
    widget.burstSignal?.addListener(_onAttackBurst);
  }

  @override
  void didUpdateWidget(GlitchOverlay old) {
    super.didUpdateWidget(old);
    if (old.burstSignal != widget.burstSignal) {
      old.burstSignal?.removeListener(_onAttackBurst);
      widget.burstSignal?.addListener(_onAttackBurst);
    }
  }

  /// Fires when the user launches an attack — an intense immediate burst.
  void _onAttackBurst() {
    if (!mounted) return;
    setState(() {
      _strips = List.generate(5 + _rng.nextInt(4), (_) {
        final isCyan = _rng.nextBool();
        return _Strip(
          y: _rng.nextDouble(),
          h: 0.008 + _rng.nextDouble() * 0.030,
          dx: (_rng.nextDouble() - 0.5) * 55,
            color: isCyan ? CyberpunkColors.cyan : CyberpunkColors.amber,
            alpha: 0.18 + _rng.nextDouble() * 0.28,
        );
      });
    });
    _ctrl.forward(from: 0);
  }

  void _schedule() {
    final ms = 1400 + _rng.nextInt(4500);
    Future.delayed(Duration(milliseconds: ms), () {
      if (!mounted) return;
      setState(() {
        _strips = List.generate(2 + _rng.nextInt(4), (_) {
          final isCyan = _rng.nextBool();
          return _Strip(
            y: _rng.nextDouble(),
            h: 0.004 + _rng.nextDouble() * 0.018,
            dx: (_rng.nextDouble() - 0.5) * 28,
            color: isCyan ? CyberpunkColors.cyan : CyberpunkColors.amber,
            alpha: 0.07 + _rng.nextDouble() * 0.16,
          );
        });
      });
      _ctrl.forward(from: 0);
    });
  }

  @override
  void dispose() {
    widget.burstSignal?.removeListener(_onAttackBurst);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        // ── Always-on: scanlines ────────────────────────────────────────
        const IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: _ScanlinePainter(),
            ),
          ),
        ),
        // ── Timed: glitch strips ────────────────────────────────────────
        if (_strips.isNotEmpty)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => CustomPaint(
                size: Size.infinite,
                painter: _GlitchPainter(
                  strips: _strips,
                  t: _ctrl.value,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Scanline painter ───────────────────────────────────────────────────────

class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Dark CRT scanlines
    final dark = Paint()
      ..color = const Color(0x14000000)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), dark);
    }
    // Subtle vignette
    final vignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.85,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      vignette,
    );
  }

  @override
  bool shouldRepaint(_ScanlinePainter _) => false;
}

// ── Glitch strip data ──────────────────────────────────────────────────────

class _Strip {
  final double y;
  final double h;
  final double dx;
  final Color color;
  final double alpha;
  const _Strip({
    required this.y,
    required this.h,
    required this.dx,
    required this.color,
    required this.alpha,
  });
}

// ── Glitch strip painter ───────────────────────────────────────────────────

class _GlitchPainter extends CustomPainter {
  final List<_Strip> strips;
  final double t; // 0→1, fades in and out via sin

  const _GlitchPainter({required this.strips, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final fade = math.sin(t * math.pi).clamp(0.0, 1.0);
    for (final s in strips) {
      final rect = Rect.fromLTWH(
        0,
        s.y * size.height,
        size.width,
        s.h * size.height,
      );
      // Primary color bar
      canvas.drawRect(
        rect,
        Paint()..color = s.color.withValues(alpha: s.alpha * fade),
      );
      // Displaced echo (simulate pixel displacement)
      canvas.drawRect(
        rect.translate(s.dx * fade, 0),
        Paint()..color = s.color.withValues(alpha: s.alpha * 0.45 * fade),
      );
      // Inverse channel echo
      canvas.drawRect(
        rect.translate(-s.dx * fade * 0.5, 0),
        Paint()
          ..color = (s.color == CyberpunkColors.cyan
                  ? CyberpunkColors.amber
                  : CyberpunkColors.cyan)
              .withValues(alpha: s.alpha * 0.2 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_GlitchPainter old) => old.t != t;
}
