import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'coastline_data.dart';

// ── Data model ────────────────────────────────────────────────────────────

class LobbyMarker {
  final double lat;
  final double lon;
  final String code;
  final int boardSize;
  final int playerCount;
  final int maxPlayers;
  final String country;

  const LobbyMarker({
    required this.lat,
    required this.lon,
    required this.code,
    required this.boardSize,
    required this.playerCount,
    required this.maxPlayers,
    this.country = '',
  });
}

// ── GlobeWidget ───────────────────────────────────────────────────────────

/// A 3D holographic globe that renders [lobbies] as glowing markers.
///
/// Users can drag to rotate and scroll/pinch to zoom.
/// Tapping a marker fires [onMarkerTap].
class GlobeWidget extends StatefulWidget {
  final List<LobbyMarker> lobbies;
  final void Function(LobbyMarker)? onMarkerTap;

  const GlobeWidget({
    super.key,
    required this.lobbies,
    this.onMarkerTap,
  });

  @override
  State<GlobeWidget> createState() => _GlobeWidgetState();
}

class _GlobeWidgetState extends State<GlobeWidget>
    with SingleTickerProviderStateMixin {
  double _yaw = 0.25;
  double _pitch = 0.22;
  double _scale = 1.0;

  // Captured at gesture start for cumulative pan + pinch.
  Offset? _gestureStart;
  double _yawAtStart = 0;
  double _pitchAtStart = 0;
  double _scaleAtStart = 1.0;

  // Tap detection state.
  DateTime? _tapStartTime;
  bool _gestureWasDrag = false;

  late final AnimationController _ticker;

  // Projected lobby positions for hit-testing — updated each paint.
  final _projected = <(LobbyMarker, Offset)>[];

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Offset? _project(double lat, double lon, Offset center, double r) {
    final la = lat * math.pi / 180;
    final lo = lon * math.pi / 180;
    final x0 = math.cos(la) * math.cos(lo);
    final y0 = math.sin(la);
    final z0 = math.cos(la) * math.sin(lo);
    // Yaw (around Y axis)
    final x1 = x0 * math.cos(_yaw) + z0 * math.sin(_yaw);
    final z1 = -x0 * math.sin(_yaw) + z0 * math.cos(_yaw);
    // Pitch (around X axis)
    final y2 = y0 * math.cos(_pitch) - z1 * math.sin(_pitch);
    final z2 = y0 * math.sin(_pitch) + z1 * math.cos(_pitch);
    if (z2 < -0.05) return null;
    return Offset(center.dx + r * x1, center.dy - r * y2);
  }

  void _rebuildProjections(Size size) {
    _projected.clear();
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 * 0.85 * _scale;
    for (final m in widget.lobbies) {
      final pt = _project(m.lat, m.lon, c, r);
      if (pt != null) _projected.add((m, pt));
    }
  }

  // ── Gesture handlers ────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) {
    _gestureStart  = d.localFocalPoint;
    _yawAtStart    = _yaw;
    _pitchAtStart  = _pitch;
    _scaleAtStart  = _scale;
    _tapStartTime  = DateTime.now();
    _gestureWasDrag = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (!_gestureWasDrag) {
      final moved = (d.localFocalPoint - _gestureStart!).distance;
      if (moved > 6 || d.scale != 1.0) _gestureWasDrag = true;
    }
    if (!_gestureWasDrag) return;
    setState(() {
      // Rotation: cumulative delta from gesture start.
      final dx = d.localFocalPoint.dx - _gestureStart!.dx;
      final dy = d.localFocalPoint.dy - _gestureStart!.dy;
      _yaw   = _yawAtStart + dx * 0.006;
      _pitch = (_pitchAtStart + dy * 0.006)
          .clamp(-math.pi / 2.05, math.pi / 2.05);
      // Zoom: two-finger pinch.
      if (d.pointerCount >= 2) {
        _scale = (_scaleAtStart * d.scale).clamp(0.5, 2.5);
      }
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (!_gestureWasDrag && _gestureStart != null && _tapStartTime != null) {
      final ms = DateTime.now().difference(_tapStartTime!).inMilliseconds;
      if (ms < 350) _hitTest(_gestureStart!);
    }
    _gestureStart   = null;
    _gestureWasDrag = false;
  }

  void _hitTest(Offset localPosition) {
    const hitRadius = 20.0;
    LobbyMarker? nearest;
    double nearestDist = double.infinity;
    for (final (marker, pt) in _projected) {
      final dist = (localPosition - pt).distance;
      if (dist < hitRadius && dist < nearestDist) {
        nearest = marker;
        nearestDist = dist;
      }
    }
    if (nearest != null) widget.onMarkerTap?.call(nearest);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Desktop scroll wheel / trackpad zoom.
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) {
          setState(() {
            _scale = (_scale - e.scrollDelta.dy * 0.001).clamp(0.5, 2.5);
          });
        }
      },
      child: GestureDetector(
        // onScale handles both 1-finger drag (rotate) and 2-finger pinch (zoom).
        onScaleStart:  _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd:    _onScaleEnd,
        child: AnimatedBuilder(
          animation: _ticker,
          builder: (context, _) {
            return LayoutBuilder(builder: (ctx, constraints) {
              final size = constraints.biggest;
              _rebuildProjections(size);
              return CustomPaint(
                size: size,
                painter: _GlobePainter(
                  yaw: _yaw,
                  pitch: _pitch,
                  scale: _scale,
                  lobbies: widget.lobbies,
                  pulse: _ticker.value,
                ),
              );
            });
          },
        ),
      ),
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────

class _GlobePainter extends CustomPainter {
  final double yaw, pitch, scale, pulse;
  final List<LobbyMarker> lobbies;

  const _GlobePainter({
    required this.yaw,
    required this.pitch,
    required this.scale,
    required this.lobbies,
    required this.pulse,
  });

  // ── Projection ─────────────────────────────────────────────────────────

  Offset? _proj(double lat, double lon, Offset c, double r) {
    final la = lat * math.pi / 180;
    final lo = lon * math.pi / 180;
    final x0 = math.cos(la) * math.cos(lo);
    final y0 = math.sin(la);
    final z0 = math.cos(la) * math.sin(lo);
    final x1 = x0 * math.cos(yaw) + z0 * math.sin(yaw);
    final z1 = -x0 * math.sin(yaw) + z0 * math.cos(yaw);
    final y2 = y0 * math.cos(pitch) - z1 * math.sin(pitch);
    final z2 = y0 * math.sin(pitch) + z1 * math.cos(pitch);
    if (z2 < -0.05) return null;
    return Offset(c.dx + r * x1, c.dy - r * y2);
  }

  // ── paint ───────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 * 0.85 * scale;
    _drawSphere(canvas, c, r);
    _drawGrid(canvas, c, r);
    _drawContinents(canvas, c, r);
    _drawLobbies(canvas, c, r);
  }

  void _drawSphere(Canvas canvas, Offset c, double r) {
    // Ambient halo
    canvas.drawCircle(
        c,
        r * 1.15,
        Paint()
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22)
          ..color = const Color(0xFF00FF88).withValues(alpha: 0.06));

    // Sphere fill — dark blue-black with subtle radial highlight
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.4),
            radius: 1.0,
            colors: const [Color(0xFF071828), Color(0xFF020C16)],
          ).createShader(Rect.fromCircle(center: c, radius: r)));

    // Edge ring
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = const Color(0xFF00FF88).withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);
  }

  void _drawGrid(Canvas canvas, Offset c, double r) {
    final p = Paint()
      ..color = const Color(0xFF00FFCC).withValues(alpha: 0.11)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Latitudes every 30°
    for (final lat in const [-60.0, -30.0, 0.0, 30.0, 60.0]) {
      _strokeParallel(canvas, c, r, lat, p);
    }
    // Longitudes every 30°
    for (var lo = -180; lo < 180; lo += 30) {
      _strokeMeridian(canvas, c, r, lo.toDouble(), p);
    }
  }

  void _strokeParallel(Canvas canvas, Offset c, double r, double lat, Paint p) {
    final path = Path();
    var started = false;
    for (var lo = -180; lo <= 180; lo += 2) {
      final pt = _proj(lat, lo.toDouble(), c, r);
      if (pt == null) {
        started = false;
        continue;
      }
      if (!started) {
        path.moveTo(pt.dx, pt.dy);
        started = true;
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(path, p);
  }

  void _strokeMeridian(Canvas canvas, Offset c, double r, double lon, Paint p) {
    final path = Path();
    var started = false;
    for (var la = -90; la <= 90; la += 2) {
      final pt = _proj(la.toDouble(), lon, c, r);
      if (pt == null) {
        started = false;
        continue;
      }
      if (!started) {
        path.moveTo(pt.dx, pt.dy);
        started = true;
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(path, p);
  }

  void _drawContinents(Canvas canvas, Offset c, double r) {
    final p = Paint()
      ..color = const Color(0xFF00FF88).withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    for (final poly in _kContinentPolygons) {
      final path = Path();
      var started = false;
      for (final pt in poly) {
        final p2 = _proj(pt[0], pt[1], c, r);
        if (p2 == null) {
          started = false;
          continue;
        }
        if (!started) {
          path.moveTo(p2.dx, p2.dy);
          started = true;
        } else {
          path.lineTo(p2.dx, p2.dy);
        }
      }
      canvas.drawPath(path, p);
    }
  }

  void _drawLobbies(Canvas canvas, Offset c, double r) {
    final pulseSin = math.sin(pulse * math.pi * 2) * 0.5 + 0.5;

    for (final lobby in lobbies) {
      final pt = _proj(lobby.lat, lobby.lon, c, r);
      if (pt == null) continue;

      // Outer pulse ring
      canvas.drawCircle(
          pt,
          5.0 + pulseSin * 6.0,
          Paint()
            ..color = const Color(0xFF8B5CF6)
                .withValues(alpha: 0.22 + 0.18 * pulseSin)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);

      // Glow
      canvas.drawCircle(
          pt,
          5.5,
          Paint()
            ..color = const Color(0xFF8B5CF6).withValues(alpha: 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));

      // Core dot
      canvas.drawCircle(
          pt,
          3.5,
          Paint()..color = Colors.white.withValues(alpha: 0.95));
    }
  }

  @override
  bool shouldRepaint(_GlobePainter o) =>
      o.yaw != yaw ||
      o.pitch != pitch ||
      o.scale != scale ||
      o.pulse != pulse ||
      o.lobbies != lobbies;
}

// ── Coastline data ──────────────────────────────────────────────────────────
// Sourced from Natural Earth 110m (coastline_data.dart, auto-generated).
// Aliased locally so the painter can reference a short name.
const List<List<List<double>>> _kContinentPolygons = kCoastlineSegments;

