import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';

// ── AudioService ─────────────────────────────────────────────────────────────

/// Plays all in-game and UI sound effects.
///
/// All WAV files live under `assets/audio/` — swap any file there to change
/// a sound without touching Dart code.
///
/// Obtain via [audioServiceProvider].  Call [toggleMute] to silence all
/// playback globally.
class AudioService {
  AudioService() {
    for (final key in _kKeys) {
      _players[key] = AudioPlayer();
    }
  }

  final Map<String, AudioPlayer> _players = {};
  bool _muted = false;

  bool get muted => _muted;
  void toggleMute() => _muted = !_muted;

  // One player slot per sound key so that rapid triggers don't stack.
  static const List<String> _kKeys = [
    'place_node',
    'capture',
    'turn_start',
    'pass_turn',
    'game_win',
    'game_over',
    'timebomb_tick',
    'boot_beep',
    'menu_select',
    'connect',
    'atk_ddos',
    'atk_trojan',
    'atk_mitm',
    'atk_backdoor',
    'atk_patch',
    'atk_worm',
    'atk_knightseye',
    'atk_psyche',
  ];

  Future<void> _play(String key) async {
    if (_muted) return;
    final player = _players[key];
    if (player == null) return;
    try {
      // Stop any previous play of this slot so rapid triggers feel responsive.
      await player.stop();
      await player.play(AssetSource('audio/$key.wav'));
    } catch (_) {
      // Audio errors must never crash the game.
    }
  }

  // ── Core gameplay ──────────────────────────────────────────────────────────

  /// Stone placed on the board: network node deployed.
  Future<void> playPlaceNode() => _play('place_node');

  /// One or more stones captured: group deleted from the network.
  Future<void> playCapture() => _play('capture');

  /// The local player's turn has begun.
  Future<void> playTurnStart() => _play('turn_start');

  /// The local player passed their turn.
  Future<void> playPass() => _play('pass_turn');

  /// Local player won the game.
  Future<void> playGameWin() => _play('game_win');

  /// Local player lost (or the game ended without a win for them).
  Future<void> playGameOver() => _play('game_over');

  /// Each tick of the psyche-attack countdown.
  Future<void> playTimebombTick() => _play('timebomb_tick');

  // ── UI ─────────────────────────────────────────────────────────────────────

  /// Lobby boot-sequence line revealed.
  Future<void> playBootBeep() => _play('boot_beep');

  /// Main-menu entry selected.
  Future<void> playMenuSelect() => _play('menu_select');

  /// Multiplayer connection established / game started.
  Future<void> playConnect() => _play('connect');

  // ── Attacks ────────────────────────────────────────────────────────────────

  /// Play the sound associated with [type].
  Future<void> playAttack(AttackType type) {
    switch (type) {
      case AttackType.ddos:
        return _play('atk_ddos');
      case AttackType.trojan:
        return _play('atk_trojan');
      case AttackType.mitm:
        return _play('atk_mitm');
      case AttackType.backdoor:
        return _play('atk_backdoor');
      case AttackType.patch:
        return _play('atk_patch');
      case AttackType.worm:
        return _play('atk_worm');
      case AttackType.knightseye:
        return _play('atk_knightseye');
      case AttackType.psyche:
        return _play('atk_psyche');
    }
  }

  void dispose() {
    for (final p in _players.values) {
      p.dispose();
    }
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final audioServiceProvider = Provider<AudioService>((ref) {
  final svc = AudioService();
  ref.onDispose(svc.dispose);
  return svc;
});
