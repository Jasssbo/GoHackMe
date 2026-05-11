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

  /// Returns the active UI scale factor.  Falls back to 1.0 if [UiScale] is
  /// not present in the widget tree (e.g. in tests).
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UiScale>()?.scale ?? 1.0;

  /// Computes the scale factor from the current [MediaQuery] size.
  ///
  /// Baseline: 720 logical-pixel shortest side.
  /// Clamped to [1.0, 1.8] so phones stay unchanged and huge 4K desktops
  /// don't over-scale.
  static double fromContext(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return (size.shortestSide / 720.0).clamp(1.0, 1.8);
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
