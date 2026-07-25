import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State notifier tracking the app's native lifecycle state.
class AppLifecycleNotifier extends Notifier<AppLifecycleState>
    with WidgetsBindingObserver {
  @override
  AppLifecycleState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
    });
    return WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    this.state = state;
  }
}

/// Riverpod provider for listening to app lifecycle state transitions.
final appLifecycleProvider =
    NotifierProvider<AppLifecycleNotifier, AppLifecycleState>(
  AppLifecycleNotifier.new,
);
