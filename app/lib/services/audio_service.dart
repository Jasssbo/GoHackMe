import 'dart:math';
import 'package:flutter/services.dart';
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
    for (int i = 0; i < _kMaxPolyphony; i++) {
      _polyphonicPool.add(AudioPlayer());
    }
  }

  static const int _kMaxPolyphony = 4;
  final List<AudioPlayer> _polyphonicPool = [];
  int _nextPoolIndex = 0;

  bool _muted = false;

  bool get muted => _muted;
  void toggleMute() => _muted = !_muted;

  Future<void> _play(String key) async {
    if (_muted) return;
    try {
      // Find an idle player slot in the pool (player not currently playing)
      AudioPlayer? player;
      for (final p in _polyphonicPool) {
        if (p.state != PlayerState.playing) {
          player = p;
          break;
        }
      }

      // If all 4 slots are busy, steal the oldest slot (round-robin)
      if (player == null) {
        player = _polyphonicPool[_nextPoolIndex];
        _nextPoolIndex = (_nextPoolIndex + 1) % _kMaxPolyphony;
        await player.stop();
      }

      await player.play(AssetSource('audio/$key.wav')).catchError((_) {});
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

  // ── Boot Sequence Audio ───────────────────────────────────────────────────
  //
  // Files are named with a numeric prefix that maps to a boot phase:
  //   1-1-*  →  startup (fired in main() before any UI)
  //   1-2-*  →  booting (screen lights up, AuthScreen initState)
  //   1-3-*  →  kernel log beeps (background, during kernel line printing)
  //   1-4-*  →  "logging" voice (AWAITED — caller wipes screen on return)
  //   1-5-*  →  user profile log beeps (background, during user line printing)
  //   2-*    →  "who are you?" voice (fires at typewriter start)
  //   3-*    →  individual connect beeps (one per connection log line)
  //   4-*    →  greetings (fired in LobbyScreen.initState)

  final List<String> _typingSounds = [];
  String? _deleteTypingSound;  // typing-name/typing-delete.mp3 — played on backspace

  String? _bootingSound;       // 1-2
  String? _kernelLogSound;     // 1-3
  String? _loggingVoiceSound;  // 1-4
  String? _userLogSound;       // 1-5
  String? _whoAreYouSound;     // 2
  final List<String> _connectBeeps = []; // 3-* sorted by filename
  String? _greetingsSound;     // 4

  bool _assetsInitialized = false;

  final List<AudioPlayer> _typingPool = List.generate(4, (_) => AudioPlayer());
  int _typingPoolIndex = 0;

  /// Number of available connect-beep files (one per connection log line).
  int get connectBeepCount => _connectBeeps.length;

  /// Dynamically scans the asset manifest and maps every MP3 in the
  /// boot-sequence folder to its phase by filename prefix.
  Future<void> _initializeBootSequenceAssets() async {
    if (_assetsInitialized) return;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final allAssets = manifest.listAssets();

      _typingSounds.clear();
      _connectBeeps.clear();
      _bootingSound = null;
      _kernelLogSound = null;
      _loggingVoiceSound = null;
      _userLogSound = null;
      _whoAreYouSound = null;
      _greetingsSound = null;

      for (final asset in allAssets) {
        if (!asset.startsWith('assets/audio/boot-sequence/')) continue;

        // typing-name subfolder
        if (asset.startsWith('assets/audio/boot-sequence/typing-name/')) {
          if (asset.endsWith('.mp3')) {
            // Keep the delete sound separate — it is never picked at random.
            if (asset.split('/').last.toLowerCase().contains('delete')) {
              _deleteTypingSound = asset;
            } else {
              _typingSounds.add(asset);
            }
          }
          continue;
        }

        if (!asset.endsWith('.mp3')) continue;
        final filename = asset.split('/').last.toLowerCase();

        if (filename.startsWith('1-2')) {
          _bootingSound = asset;
        } else if (filename.startsWith('1-3')) {
          _kernelLogSound = asset;
        } else if (filename.startsWith('1-4')) {
          _loggingVoiceSound = asset;
        } else if (filename.startsWith('1-5')) {
          _userLogSound = asset;
        } else if (filename.startsWith('2')) {
          _whoAreYouSound = asset;
        } else if (filename.startsWith('3')) {
          _connectBeeps.add(asset);
        } else if (filename.startsWith('4')) {
          _greetingsSound = asset;
        }
        // 1-1 is handled directly in main() — not needed here.
      }

      // Sort connect beeps by filename: 3-beep.mp3 < 3-beep2.mp3 < … < 3-beep9.mp3
      _connectBeeps.sort(
        (a, b) => a.split('/').last.compareTo(b.split('/').last),
      );

      _assetsInitialized = true;
    } catch (_) {
      // Audio errors must never crash the game.
    }
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  AudioPlayer _getPoolPlayer() {
    AudioPlayer? player;
    for (final p in _polyphonicPool) {
      if (p.state != PlayerState.playing) {
        player = p;
        break;
      }
    }
    if (player == null) {
      player = _polyphonicPool[_nextPoolIndex];
      _nextPoolIndex = (_nextPoolIndex + 1) % _kMaxPolyphony;
    }
    return player;
  }

  /// Fire-and-forget: starts [assetPath] using a pooled player.
  Future<void> _fireAndForget(String? assetPath) async {
    if (_muted || assetPath == null) return;
    try {
      final player = _getPoolPlayer();
      await player.stop();
      await player.play(AssetSource(assetPath.replaceFirst('assets/', ''))).catchError((_) {});
    } catch (_) {}
  }

  /// Awaited: plays [assetPath] using a pooled player and awaits completion.
  Future<void> _playAndAwait(String? assetPath) async {
    if (_muted || assetPath == null) return;
    try {
      final player = _getPoolPlayer();
      await player.stop();
      await player.play(AssetSource(assetPath.replaceFirst('assets/', ''))).catchError((_) {});
      await player.onPlayerComplete.first.timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  // ── Phase 1-2: Screen lights up ───────────────────────────────────────────

  /// Called from [AuthScreen.initState] the moment the screen becomes visible.
  Future<void> playBootingSound() async {
    await _initializeBootSequenceAssets();
    await _fireAndForget(_bootingSound);
  }

  // ── Phase 1-3: Kernel log beeps ───────────────────────────────────────────

  /// Plays in the background while kernel lines are printing.  Fire-and-forget.
  Future<void> playKernelLogSound() async {
    await _initializeBootSequenceAssets();
    await _fireAndForget(_kernelLogSound);
  }

  // ── Phase 1-4: "logging" voice ────────────────────────────────────────────

  /// **Awaited.** The caller should wipe the kernel lines from the screen
  /// as soon as this future completes.
  Future<void> playLoggingVoiceAndAwait() async {
    await _initializeBootSequenceAssets();
    await _playAndAwait(_loggingVoiceSound);
  }

  // ── Phase 1-5: User profile log beeps ────────────────────────────────────

  /// Plays in the background while user-profile lines are printing.
  Future<void> playUserLogSound() async {
    await _initializeBootSequenceAssets();
    await _fireAndForget(_userLogSound);
  }

  // ── Phase 2: "who are you?" voice ────────────────────────────────────────

  /// Fires at the moment the first character of the typewriter appears.
  Future<void> playWhoAreYouVoice() async {
    await _initializeBootSequenceAssets();
    await _fireAndForget(_whoAreYouSound);
  }

  // ── Phase 3: Individual connect beeps ────────────────────────────────────

  /// Plays the [index]-th connect-beep file and **awaits** its completion so
  /// the caller can print the next connection log line in lockstep.
  Future<void> playConnectBeep(int index) async {
    await _initializeBootSequenceAssets();
    if (index < 0 || index >= _connectBeeps.length) return;
    await _playAndAwait(_connectBeeps[index]);
  }

  // ── Phase 4: Greetings ────────────────────────────────────────────────────

  /// Fired in [LobbyScreen.initState] the moment the lobby is pushed.
  Future<void> playGreetings() async {
    await _initializeBootSequenceAssets();
    await _fireAndForget(_greetingsSound);
  }

  // ── Typing sounds ────────────────────────────────────────────────────────

  /// Plays a random typing sound from the typing-name folder.
  /// Does NOT include the delete sound — use [playDeleteTypingSound] for that.
  Future<void> playRandomTypingSound() async {
    await _initializeBootSequenceAssets();
    if (_muted || _typingSounds.isEmpty) return;
    try {
      final idx = Random().nextInt(_typingSounds.length);
      final asset = _typingSounds[idx];
      final player = _typingPool[_typingPoolIndex];
      _typingPoolIndex = (_typingPoolIndex + 1) % _typingPool.length;
      await player.stop();
      await player.play(AssetSource(asset.replaceFirst('assets/', ''))).catchError((_) {});
    } catch (_) {
      // Audio errors must never crash the game.
    }
  }

  /// Plays `typing-delete.mp3` — used specifically when the user presses
  /// backspace or the delete key in the name input.
  Future<void> playDeleteTypingSound() async {
    await _initializeBootSequenceAssets();
    if (_muted || _deleteTypingSound == null) return;
    try {
      final player = _typingPool[_typingPoolIndex];
      _typingPoolIndex = (_typingPoolIndex + 1) % _typingPool.length;
      await player.stop();
      await player.play(AssetSource(_deleteTypingSound!.replaceFirst('assets/', ''))).catchError((_) {});
    } catch (_) {
      // Audio errors must never crash the game.
    }
  }

  void dispose() {
    for (final p in _polyphonicPool) {
      p.dispose();
    }
    for (final p in _typingPool) {
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
