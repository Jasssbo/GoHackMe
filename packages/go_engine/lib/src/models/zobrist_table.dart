import 'dart:math';

import 'stone_color.dart';

/// Pre-computed Zobrist random table for superko (full-board Ko) detection.
///
/// A Zobrist hash is the XOR of one deterministic random value per
/// (position, color) pair for every stone currently on the board.  Because
/// XOR is its own inverse, adding or removing a single stone is O(1):
/// just XOR in (or out) that stone's table entry.
///
/// The table is initialised once with a fixed seed, so values are identical
/// for the lifetime of the process.  [boardHashes] are never transmitted
/// over the network, so cross-device consistency is not required — only
/// within-session consistency, which [static final] already guarantees.
///
/// Collision probability per comparison: ≈ 1 / 2^62.
/// For a 300-move game P(any collision) ≈ n² / 2^62 ≈ 2×10⁻¹⁴ — negligible.
class ZobristTable {
  ZobristTable._();

  static const int _maxBoardSize = 19;

  /// table[x][y][colorIndex] → unique 62-bit random value.
  static final List<List<List<int>>> _table = _buildTable();

  static List<List<List<int>>> _buildTable() {
    final rng = Random(0x47C3A2B1); // fixed seed → deterministic table
    return List.generate(
      _maxBoardSize,
      (_) => List.generate(
        _maxBoardSize,
        (_) => List.generate(
          StoneColor.values.length,
          (_) {
            // Combine two 31-bit values into a 62-bit value.
            // Random.nextInt(max) requires max ≤ 2^32; 1<<31 = 2^31 is valid.
            final hi = rng.nextInt(1 << 31);
            final lo = rng.nextInt(1 << 31);
            return (hi << 31) | lo;
          },
        ),
      ),
    );
  }

  /// Returns the Zobrist value for [color] at board coordinate ([x], [y]).
  static int valueFor(int x, int y, StoneColor color) =>
      _table[x][y][color.index];
}
