import 'position.dart';
import 'stone_color.dart';

/// An immutable Go board.
///
/// The board is a [size]×[size] grid where intersections may hold a stone
/// ([StoneColor]) or be empty (null).  All mutations return a new [Board].
class Board {
  final int size;

  /// Internal stone map.  Positions not present are empty.
  final Map<Position, StoneColor> _stones;

  Board({required this.size, Map<Position, StoneColor>? stones})
      : _stones = stones != null ? Map.unmodifiable(stones) : const {};

  // ── Queries ───────────────────────────────────────────────────────────────

  /// Returns the stone at [pos], or null if the intersection is empty.
  StoneColor? at(Position pos) => _stones[pos];

  /// Returns true if [pos] is within the board boundaries.
  bool isInBounds(Position pos) =>
      pos.x >= 0 && pos.x < size && pos.y >= 0 && pos.y < size;

  /// Returns in-bounds orthogonal neighbors of [pos].
  List<Position> neighborsOf(Position pos) =>
      pos.rawNeighbors.where(isInBounds).toList();

  /// Unmodifiable view of all stones currently on the board.
  Map<Position, StoneColor> get stones => _stones;

  bool get isEmpty => _stones.isEmpty;

  // ── Mutations (return new Board) ──────────────────────────────────────────

  /// Returns a new board with [color] placed at [pos].
  /// Does NOT validate Go rules – use [GoRules.validatePlacement] first.
  Board place(Position pos, StoneColor color) {
    final next = Map<Position, StoneColor>.from(_stones)..[pos] = color;
    return Board(size: size, stones: next);
  }

  /// Returns a new board with all [positions] removed.
  Board remove(Set<Position> positions) {
    final next = Map<Position, StoneColor>.from(_stones)
      ..removeWhere((k, _) => positions.contains(k));
    return Board(size: size, stones: next);
  }

  // ── Equality (needed for Ko detection) ───────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Board || size != other.size) return false;
    if (_stones.length != other._stones.length) return false;
    for (final entry in _stones.entries) {
      if (other._stones[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        size,
        Object.hashAllUnordered(
          _stones.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );

  @override
  String toString() => 'Board(${size}x$size, ${_stones.length} stones)';
}
