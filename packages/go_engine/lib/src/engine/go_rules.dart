import '../models/board.dart';
import '../models/position.dart';
import '../models/stone_color.dart';

/// Pure-function Go rule implementation.
///
/// All methods are static and side-effect free.  The board passed in is
/// never mutated; every result is a new [Board].
class GoRules {
  GoRules._();

  // ── Group & liberty primitives ────────────────────────────────────────────

  /// Returns all positions belonging to the connected group that includes
  /// [start].  Returns an empty set if [start] is empty.
  static Set<Position> findGroup(Board board, Position start) {
    final color = board.at(start);
    if (color == null) return const {};

    final visited = <Position>{};
    final queue = <Position>[start];

    while (queue.isNotEmpty) {
      final pos = queue.removeLast();
      if (!visited.add(pos)) continue; // already seen
      for (final neighbor in board.neighborsOf(pos)) {
        if (board.at(neighbor) == color) queue.add(neighbor);
      }
    }
    return visited;
  }

  /// Returns the set of empty intersections adjacent to any stone in [group].
  static Set<Position> libertiesOf(Board board, Set<Position> group) {
    final liberties = <Position>{};
    for (final pos in group) {
      for (final neighbor in board.neighborsOf(pos)) {
        if (board.at(neighbor) == null) liberties.add(neighbor);
      }
    }
    return liberties;
  }

  // ── Capture ───────────────────────────────────────────────────────────────

  /// After [color] places a stone at [pos] on [board], removes all opponent
  /// groups that have zero liberties.
  ///
  /// Returns a record of (boardAfterCaptures, capturedPositions).
  static (Board, Set<Position>) applyCapturesAfterPlacement(
    Board board,
    Position pos,
    StoneColor color,
  ) {
    var current = board;
    final captured = <Position>{};

    // Only look at neighbors – those are the only groups that could lose
    // their last liberty.
    final seen = <Position>{};
    for (final neighbor in board.neighborsOf(pos)) {
      final neighborColor = current.at(neighbor);
      if (neighborColor == null || neighborColor == color) continue;
      if (seen.contains(neighbor)) continue;

      final group = findGroup(current, neighbor);
      seen.addAll(group);

      if (libertiesOf(current, group).isEmpty) {
        captured.addAll(group);
        current = current.remove(group);
      }
    }

    return (current, captured);
  }

  // ── Move validation ───────────────────────────────────────────────────────

  /// Validates whether [color] may place a stone at [pos] on [board].
  ///
  /// [boardHashes] contains [Board.zobristHash] for every prior position,
  /// oldest first.  Hash comparison is O(n) over the history length, which
  /// is negligible for typical game lengths (a few hundred moves at most).
  ///
  /// Returns `null` when the move is legal; returns an error string otherwise.
  static String? validatePlacement(
    Board board,
    Position pos,
    StoneColor color,
    List<int> boardHashes,
  ) {
    if (!board.isInBounds(pos)) return 'OUT_OF_BOUNDS';
    if (board.at(pos) != null) return 'INTERSECTION_OCCUPIED';

    // Tentatively place the stone
    final boardWithStone = board.place(pos, color);

    // Apply captures that the placement would trigger
    final (boardAfterCaptures, _) =
        applyCapturesAfterPlacement(boardWithStone, pos, color);

    // Suicide check: the placed group must have at least one liberty after
    // all captures have been resolved.
    final placedGroup = findGroup(boardAfterCaptures, pos);
    if (libertiesOf(boardAfterCaptures, placedGroup).isEmpty) {
      return 'SUICIDE_NOT_ALLOWED';
    }

    // Superko check: the resulting board must not match any previous state.
    final resultHash = boardAfterCaptures.zobristHash;
    if (boardHashes.contains(resultHash)) return 'KO_VIOLATION';

    return null; // ✔ legal
  }

  // ── Convenience: apply a legal placement ─────────────────────────────────

  /// Places [color] at [pos], applies captures, and returns the resulting
  /// board together with the set of captured positions.
  ///
  /// Assumes the move has already been validated via [validatePlacement].
  static (Board, Set<Position>) applyPlacement(
    Board board,
    Position pos,
    StoneColor color,
  ) {
    final boardWithStone = board.place(pos, color);
    return applyCapturesAfterPlacement(boardWithStone, pos, color);
  }
}
