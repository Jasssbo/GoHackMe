import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Persists the list of display names the user has authenticated with.
/// The file lives inside the app's support directory so it is removed
/// when the app is uninstalled (on mobile) or the data folder is cleared.
class NameHistoryService {
  static const _fileName = 'name_history.txt';
  static const _maxNames = 10;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Returns all previously used display names (oldest first, deduplicated).
  static Future<List<String>> getNames() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final lines = await f.readAsLines();
      // Return non-empty unique names preserving order
      final seen = <String>{};
      return lines.where((l) => l.trim().isNotEmpty && seen.add(l.trim())).toList();
    } catch (_) {
      return [];
    }
  }

  /// Adds [name] to the history file if it is not already the last entry.
  static Future<void> addName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    try {
      final f = await _file();
      final existing = await getNames();
      // Move name to end (most-recent) keeping list unique
      existing.remove(trimmed);
      existing.add(trimmed);
      // Cap at _maxNames — drop the oldest entries first
      final capped = existing.length > _maxNames
          ? existing.sublist(existing.length - _maxNames)
          : existing;
      await f.writeAsString(capped.join('\n'));
    } catch (_) {
      // Non-critical – silently ignore I/O errors.
    }
  }
}
