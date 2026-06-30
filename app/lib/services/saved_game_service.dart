import 'dart:convert';
import 'dart:io';

import 'package:go_engine/go_engine.dart';
import 'package:path_provider/path_provider.dart';

// ── SavedGame model ───────────────────────────────────────────────────────

/// A game snapshot stored locally on the player's device.
class SavedGame {
  /// Unique identifier for this save file.
  final String saveId;

  /// Human-readable label shown in the resume list (e.g. "LAN – 3 players").
  final String label;

  /// ISO-8601 timestamp of when the game was saved.
  final DateTime savedAt;

  /// Board size (e.g. 9, 13, 19).
  final int boardSize;

  /// Number of players in the saved game.
  final int playerCount;

  /// 0-based index of the player slot that belongs to the saver.
  final int saverPlayerIndex;

  /// Full game state snapshot.
  final GameState state;

  /// Copy of every [Player] from the saved state (for display in the UI).
  List<Player> get players => state.players;

  const SavedGame({
    required this.saveId,
    required this.label,
    required this.savedAt,
    required this.boardSize,
    required this.playerCount,
    required this.saverPlayerIndex,
    required this.state,
  });

  Map<String, dynamic> toJson() => {
        'saveId': saveId,
        'label': label,
        'savedAt': savedAt.toUtc().toIso8601String(),
        'boardSize': boardSize,
        'playerCount': playerCount,
        'saverPlayerIndex': saverPlayerIndex,
        'state': state.toJson(),
      };

  factory SavedGame.fromJson(Map<String, dynamic> json) => SavedGame(
        saveId: json['saveId'] as String,
        label: json['label'] as String,
        savedAt: DateTime.parse(json['savedAt'] as String),
        boardSize: json['boardSize'] as int,
        playerCount: json['playerCount'] as int,
        saverPlayerIndex: json['saverPlayerIndex'] as int,
        state: GameState.fromJson(json['state'] as Map<String, dynamic>),
      );
}

// ── SavedGameService ──────────────────────────────────────────────────────

/// Persists game snapshots as individual JSON files inside the app's support
/// directory (`saved_games/` sub-folder).  Each save is its own file named
/// `<saveId>.json` so they can be deleted independently.
class SavedGameService {
  static const _dirName = 'saved_games';

  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Persists a new game snapshot and returns the [SavedGame] record.
  static Future<SavedGame> save({
    required GameState state,
    required int saverPlayerIndex,
    required String label,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final saved = SavedGame(
      saveId: id,
      label: label,
      savedAt: DateTime.now().toUtc(),
      boardSize: state.board.size,
      playerCount: state.players.length,
      saverPlayerIndex: saverPlayerIndex,
      state: state,
    );
    final dir = await _dir();
    final file = File('${dir.path}/$id.json');
    await file.writeAsString(jsonEncode(saved.toJson()));
    return saved;
  }

  /// Returns all saved games sorted newest-first.
  static Future<List<SavedGame>> listSaves() async {
    try {
      final dir = await _dir();
      final files = dir.listSync().whereType<File>().toList();
      final saves = <SavedGame>[];
      for (final f in files) {
        if (!f.path.endsWith('.json')) continue;
        try {
          final raw = await f.readAsString();
          saves.add(SavedGame.fromJson(jsonDecode(raw) as Map<String, dynamic>));
        } catch (_) {
          // Corrupted save — skip silently.
        }
      }
      saves.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return saves;
    } catch (_) {
      return [];
    }
  }

  /// Deletes the save with the given [saveId]. Silent no-op if not found.
  static Future<void> delete(String saveId) async {
    try {
      final dir = await _dir();
      final file = File('${dir.path}/$saveId.json');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
