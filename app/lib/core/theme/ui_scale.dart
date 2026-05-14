import 'package:flutter/material.dart';

/// Screen-size-relative UI scale helper.
///
/// The scale is 1.0 at the baseline (≤720 logical pixels on the shortest
/// side — all typical phones) and grows linearly up to 1.8 for large desktop
/// displays (e.g. a 1296 px shortest side on a 1440 p monitor).
///
/// **Text** is scaled globally in [main.dart] via [MediaQuery.textScaler], so
/// no individual [Text] widgets need to be changed.
///
/// Use [UiScale.of] / the [UiScaleExt] extension to scale spacing and layout
/// dimensions that are not driven by text metrics (container widths, paddings,
/// [SizedBox] heights, etc.).
class UiScale extends InheritedWidget {
  const UiScale({super.key, required this.scale, required super.child});

  final double scale;

  // Baseline shortest-side in logical pixels: all typical phones are at or
  // below this, so scale stays at 1.0 on mobile and grows on large screens.
  static const _kBaselineSide = 720.0;

  /// Returns the active UI scale factor (falls back to 1.0 if not in tree).
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UiScale>()?.scale ?? 1.0;

  /// Computes the scale factor from the current [MediaQuery] size.
  ///
  /// Clamped to [1.0, 1.8]: phones stay at 1.0, large 4K desktops cap at 1.8.
  static double fromContext(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return (size.shortestSide / _kBaselineSide).clamp(1.0, 1.8);
  }

  @override
  bool updateShouldNotify(UiScale old) => old.scale != scale;
}

extension UiScaleExt on BuildContext {
  /// The active UI scale factor.
  double get uiScale => UiScale.of(this);

  /// Scale a layout dimension (spacing, border width, container size, …).
  double s(double value) => value * uiScale;

  /// Scale a font size.  Semantically separate from [s] for clarity.
  double sp(double value) => value * uiScale;
}
