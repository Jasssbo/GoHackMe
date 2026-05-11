import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../services/name_history_service.dart';

/// Holds the locally-stored player identity (display name + stable UUID).
class AuthState {
  final String playerId;
  final String displayName;

  const AuthState({required this.playerId, required this.displayName});

  AuthState copyWith({String? displayName}) => AuthState(
        playerId: playerId,
        displayName: displayName ?? this.displayName,
      );
}

class AuthNotifier extends AsyncNotifier<AuthState> {
  static const _keyName = 'display_name';

  @override
  Future<AuthState> build() async {
    final prefs = await SharedPreferences.getInstance();
    // Generate a fresh session-scoped ID every launch so two instances
    // on the same machine never collide.
    final id = const Uuid().v4();
    final name = prefs.getString(_keyName) ?? '';
    return AuthState(playerId: id, displayName: name);
  }

  Future<void> setDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, name);
    await NameHistoryService.addName(name);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(displayName: name));
    }
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
