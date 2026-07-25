import 'package:flutter_riverpod/flutter_riverpod.dart';

enum PerformanceMode {
  high('high', 'HIGH_PERFORMANCE', 'Full 60 FPS ambient pulses and CRT flicker.'),
  powerSave('save', 'POWER_SAVE', 'Static glow mode. Disables tickers to allow GPU 0 FPS idle.');

  final String code;
  final String label;
  final String description;

  const PerformanceMode(this.code, this.label, this.description);

  static PerformanceMode fromCode(String code) {
    final normalized = code.trim().toLowerCase();
    if (normalized == 'low' || normalized == 'save' || normalized == 'powersave') {
      return PerformanceMode.powerSave;
    }
    return PerformanceMode.high;
  }
}

class PerformanceNotifier extends Notifier<PerformanceMode> {
  @override
  PerformanceMode build() => PerformanceMode.high;

  void setMode(PerformanceMode mode) {
    state = mode;
  }

  bool setByCode(String code) {
    final mode = PerformanceMode.fromCode(code);
    state = mode;
    return true;
  }
}

final performanceModeProvider =
    NotifierProvider<PerformanceNotifier, PerformanceMode>(
  PerformanceNotifier.new,
);
