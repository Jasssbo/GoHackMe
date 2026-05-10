import 'package:go_engine/go_engine.dart';

void main() {
  // Example: create a new 9x9 game with 2 players.
  final state = GameState.newGame(
    players: [
      Player(id: 'p1', displayName: 'HACKER_1'),
      Player(id: 'p2', displayName: 'HACKER_2'),
    ],
    boardSize: 9,
  );
  print('Game started. Turn: ${state.turnNumber}');
}
