import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_engine/go_engine.dart';

import 'board_painter.dart';

/// Interactive, rotatable 3-D Go board widget.
///
/// **Interaction model**
/// - Single-finger **tap**    → place stone (fires [onTap]).
/// - Single-finger **drag**   → orbit: changes azimuth and elevation.
/// - Two-finger **pinch**     → zoom in / out.
/// - Two-finger **rotation**  → spin the board (azimuth).
/// - Two-finger **pan**       → also adjusts elevation.
///
/// Touching anywhere in the widget — including outside the board itself —
/// triggers the orbit gesture, making it easy to reposition the view.
class BoardWidget extends StatefulWidget {
  final Board board;
  final int boardSize;
  final Position? lastPlaced;
  final void Function(Position pos)? onTap;

  /// The stone color of the player whose turn it currently is.
  /// When non-null, that player's stones will blink gently.
  final StoneColor? activePlayerColor;

  const BoardWidget({
    super.key,
    required this.board,
    required this.boardSize,
    this.lastPlaced,
    this.onTap,
    this.activePlayerColor,
  });

  @override
  State<BoardWidget> createState() => _BoardWidgetState();
}

class _BoardWidgetState extends State<BoardWidget>
    with TickerProviderStateMixin {
  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final AnimationController _packetCtrl;  // data packet travel
  late final AnimationController _flickerCtrl; // CRT flicker
  late final AnimationController _turnCtrl;    // active-player turn blink
  double _flickerAlpha = 0.0;

  // ── View state ────────────────────────────────────────────────────────────
  double _azimuth   = math.pi / 4;     // 45° — classic isometric
  double _elevation = math.asin(0.52); // ≈31° — matches original cell ratio
  double _zoom      = 1.0;

  // Values captured at the start of each scale gesture for relative changes.
  double _gsAzimuth   = 0;
  double _gsZoom      = 1;

  // Tap-detection state.
  Offset?   _tapLocalPos;
  DateTime? _tapStartTime;
  bool      _gestureWasDrag = false;

  // Cached canvas size, updated inside LayoutBuilder each build.
  Size _canvasSize = Size.zero;

  static const double _azSens  = 0.007; // rad per screen-pixel
  static const double _elSens  = 0.005; // rad per screen-pixel
  static const double _minEl   = 0.15;  // ≈ 8.6° — prevents top-down edge case
  static const double _maxEl   = math.pi / 2 - 0.05; // ≈ 87°

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    // Packets travel across the network every ~4 s
    _packetCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();

    // Occasional low-frequency CRT flicker
    _flickerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _scheduleFlicker();

    // Gentle turn-indicator blink (slow, not jarring)
    _turnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  void _scheduleFlicker() {
    Future.delayed(
      Duration(milliseconds: 3000 + math.Random().nextInt(5000)),
      () {
        if (!mounted) return;
        _flickerCtrl.forward(from: 0).then((_) {
          if (!mounted) return;
          setState(() => _flickerAlpha = 0.0);
          _scheduleFlicker();
        });
        setState(() => _flickerAlpha = 0.6 + math.Random().nextDouble() * 0.4);
      },
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _packetCtrl.dispose();
    _flickerCtrl.dispose();
    _turnCtrl.dispose();
    super.dispose();
  }

  // ── Gesture handlers ──────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) {
    _gsAzimuth      = _azimuth;
    _gsZoom         = _zoom;
    _tapLocalPos    = d.localFocalPoint;
    _tapStartTime   = DateTime.now();
    _gestureWasDrag = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // Cross the drag threshold?
    if (!_gestureWasDrag) {
      final moved = (d.localFocalPoint - _tapLocalPos!).distance;
      if (moved > 6 || d.scale != 1.0) _gestureWasDrag = true;
    }

    if (_gestureWasDrag) {
      setState(() {
        if (d.pointerCount >= 2) {
          // Two-finger: pinch = zoom, rotation = azimuth, vertical pan = tilt.
          _zoom      = (_gsZoom * d.scale).clamp(0.35, 4.0);
          _azimuth   = _gsAzimuth + d.rotation;
          _elevation = (_elevation - d.focalPointDelta.dy * _elSens)
              .clamp(_minEl, _maxEl);
        } else {
          // Single-finger drag: orbit.
          _azimuth  += d.focalPointDelta.dx * _azSens;
          _elevation = (_elevation - d.focalPointDelta.dy * _elSens)
              .clamp(_minEl, _maxEl);
        }
      });
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // If no drag and under 350 ms, treat it as a tap.
    if (!_gestureWasDrag && widget.onTap != null) {
      final ms = DateTime.now().difference(_tapStartTime!).inMilliseconds;
      if (ms < 350 && _tapLocalPos != null) {
        final pos = board3dHitTest(
          _tapLocalPos!,
          _canvasSize,
          widget.boardSize,
          _azimuth,
          _elevation,
          _zoom,
        );
        if (pos != null) widget.onTap!(pos);
      }
    }
    _tapLocalPos    = null;
    _tapStartTime   = null;
    _gestureWasDrag = false;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : w;
        _canvasSize = Size(w, h);

        return Listener(
          // Desktop scroll wheel / trackpad zoom.
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              setState(() {
                _zoom = (_zoom - e.scrollDelta.dy * 0.002).clamp(0.35, 4.0);
              });
            }
          },
          child: GestureDetector(
            onScaleStart:  _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd:    _onScaleEnd,
            child: AnimatedBuilder(
            animation: Listenable.merge([_pulseCtrl, _packetCtrl, _flickerCtrl, _turnCtrl]),
            builder: (_, __) => RepaintBoundary(
              child: CustomPaint(
                size: _canvasSize,
                painter: BoardPainter(
                  board:             widget.board,
                  boardSize:         widget.boardSize,
                  lastPlaced:        widget.lastPlaced,
                  starPulse:         _pulseCtrl.value,
                  packetPhase:       _packetCtrl.value,
                  flickerAlpha:      _flickerAlpha,
                  azimuth:           _azimuth,
                  elevation:         _elevation,
                  zoom:              _zoom,
                  activePlayerColor: widget.activePlayerColor,
                  activePulse:       _turnCtrl.value,
                ),
              ),
            ),
          ),
        ),
      );
      },
    );
  }
}