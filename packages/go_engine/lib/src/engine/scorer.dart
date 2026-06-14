import '../models/board.dart';
import '../models/position.dart';
import '../models/stone_color.dart';

/// Scoring algorithms for GoHackMe.
///
/// GoHackMe uses a simplified **area scoring** rule (similar to Chinese rules):
///
///   score(player) = live_stones_on_board + enclosed_empty_intersections
///
/// This sidesteps the dead-stone-removal negotiation problem inherent to
/// Japanese territory scoring – appropriate for a fast-paced online variant.
class Scorer {
  Scorer._();

  // ── Area scoring ─────────────────────────────────────────────────────────

  /// Computes the area score for every player at the end of the game.
  ///
  /// Returns a map from [StoneColor] to integer score.
  static Map<StoneColor, int> areaScore(Board board) {
    final scores = <StoneColor, int>{for (final c in StoneColor.values) c: 0};

    // Count live stones
    for (final entry in board.stones.entries) {
      scores[entry.value] = scores[entry.value]! + 1;
    }

    // Count controlled empty intersections
    final counted = <Position>{};
    for (int y = 0; y < board.size; y++) {
      for (int x = 0; x < board.size; x++) {
        final pos = Position(x, y);
        if (board.at(pos) != null) continue;
        if (counted.contains(pos)) continue;

        // Flood-fill the empty region
        final region = _floodFillEmpty(board, pos);
        counted.addAll(region);

        // Determine which colours border this region
        final borderColors = <StoneColor>{};
        for (final emptyPos in region) {
          for (final neighbor in board.neighborsOf(emptyPos)) {
            final stone = board.at(neighbor);
            if (stone != null) borderColors.add(stone);
          }
        }

        // If exactly one colour borders the region, it controls the territory
        if (borderColors.length == 1) {
          final owner = borderColors.first;
          scores[owner] = scores[owner]! + region.length;
        }
      }
    }

    return scores;
  }

  // ── Territory regions (for scoring overlay) ──────────────────────────────

  /// Returns a map of empty [Position]s → controlling [StoneColor] for every
  /// empty intersection that is surrounded by exactly one player's stones.
  ///
  /// Positions touched by more than one player (contested) are omitted.
  /// Use this to drive the board's scoring-phase territory overlay.
  static Map<Position, StoneColor> territoryRegions(Board board) {
    final result  = <Position, StoneColor>{};
    final counted = <Position>{};

    for (int y = 0; y < board.size; y++) {
      for (int x = 0; x < board.size; x++) {
        final pos = Position(x, y);
        if (board.at(pos) != null) continue;
        if (counted.contains(pos)) continue;

        final region = _floodFillEmpty(board, pos);
        counted.addAll(region);

        final borderColors = <StoneColor>{};
        for (final emptyPos in region) {
          for (final neighbor in board.neighborsOf(emptyPos)) {
            final stone = board.at(neighbor);
            if (stone != null) borderColors.add(stone);
          }
        }

        if (borderColors.length == 1) {
          for (final p in region) {
            result[p] = borderColors.first;
          }
        }
      }
    }

    return result;
  }

  // ── Subnet bonus at placement ─────────────────────────────────────────────

  /// Returns how many subnets a player earns by placing at [pos].
  ///
  /// The formula rewards capturing opponent stones and growing influence:
  ///   base 1 subnet per placement
  ///   +1 per captured stone (already removed from board when this is called)
  ///   +1 bonus for placing on a star-point position (influence node)
  static int subnetsForPlacement(
    Board board,
    Position pos,
    int captureCount,
  ) {
    int earned = 1; // base
    earned += captureCount; // capture bonus

    // Influence-node bonus (star points on a 19×19)
    if (_isStarPoint(pos, board.size)) earned += 1;

    return earned;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Set<Position> _floodFillEmpty(Board board, Position start) {
    final visited = <Position>{};
    final queue = <Position>[start];

    while (queue.isNotEmpty) {
      final pos = queue.removeLast();
      if (!visited.add(pos)) continue;
      for (final neighbor in board.neighborsOf(pos)) {
        if (board.at(neighbor) == null) queue.add(neighbor);
      }
    }
    return visited;
  }

  static bool _isStarPoint(Position pos, int size) {
    // 0-indexed star-point coordinates for standard board sizes.
    // 9×9:  corners (2,2)/(2,6)/(6,2)/(6,6) + sides + tengen (4,4)
    // 13×13: corners (3,3) etc. + tengen (6,6)
    // 19×19: corners (3,3) etc. + tengen (9,9)
    const starPoints9 = {2, 4, 6};
    const starPoints13 = {3, 6, 9};
    const starPoints19 = {3, 9, 15};

    Set<int> stars;
    if (size == 9) {
      stars = starPoints9;
    } else if (size == 13) {
      stars = starPoints13;
    } else if (size == 19) {
      stars = starPoints19;
    } else {
      return false;
    }

    return stars.contains(pos.x) && stars.contains(pos.y);
  }
}

/// Final score entry for a single player.
class PlayerScore {
  final String playerId;
  final StoneColor color;
  final int areaScore;
  final int totalSubnetsEarned;
  final int capturesTotal;

  const PlayerScore({
    required this.playerId,
    required this.color,
    required this.areaScore,
    required this.totalSubnetsEarned,
    required this.capturesTotal,
  });

  /// Combined ranking score (area + subnet economy performance).
  int get rankScore => areaScore + (totalSubnetsEarned ~/ 3);

  @override
  String toString() =>
      'PlayerScore($playerId: area=$areaScore subnets=$totalSubnetsEarned)';
}
