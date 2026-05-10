/// A coordinate on the Go board.
///
/// [x] is the column (0 = leftmost), [y] is the row (0 = topmost).
/// The class is intentionally value-typed: two [Position] objects with the
/// same coordinates are always equal.
class Position {
  final int x;
  final int y;

  const Position(this.x, this.y);

  /// Returns the four orthogonal neighbors *without* bounds-checking.
  /// Use [Board.neighborsOf] if you need in-bounds filtering.
  List<Position> get rawNeighbors => [
        Position(x - 1, y),
        Position(x + 1, y),
        Position(x, y - 1),
        Position(x, y + 1),
      ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Position && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x,$y)';
}
