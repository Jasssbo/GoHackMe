/// The colour / owner of a stone on the board.
///
/// GoHackMe supports up to 4 simultaneous players, so instead of the
/// traditional Black/White we use player-index colours.  The UI maps
/// each colour to a cyberpunk palette entry.
enum StoneColor {
  p1, // Player 1 – cyan
  p2, // Player 2 – magenta
  p3, // Player 3 – yellow-green
  p4; // Player 4 – red-orange

  /// Human-readable label used in terminal-style UI messages.
  String get label => switch (this) {
        p1 => 'PLAYER_1',
        p2 => 'PLAYER_2',
        p3 => 'PLAYER_3',
        p4 => 'PLAYER_4',
      };

  /// Mapping from zero-based player index to [StoneColor].
  static StoneColor fromIndex(int index) => StoneColor.values[index % 4];
}
