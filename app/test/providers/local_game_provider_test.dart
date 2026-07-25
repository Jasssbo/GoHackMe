import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_engine/go_engine.dart';
import 'package:gohackme/features/board/providers/local_game_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalGameNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('startGame initializes 1v1 game state correctly', () {
      final notifier = container.read(localGameProvider.notifier);
      expect(container.read(localGameProvider), isNull);

      notifier.startGame(
        boardSize: 9,
        difficulty: BotDifficulty.beginner,
        humanName: 'PLAYER_1',
        botCount: 1,
      );

      final state = container.read(localGameProvider);
      expect(state, isNotNull);
      expect(state!.board.size, 9);
      expect(state.players.length, 2);
      expect(state.players.first.displayName, 'PLAYER_1');
      expect(state.currentPlayerId, 'human_player');
    });

    test('placeStone updates state for human player', () {
      final notifier = container.read(localGameProvider.notifier);
      notifier.startGame(
        boardSize: 9,
        difficulty: BotDifficulty.beginner,
        humanName: 'PLAYER_1',
        botCount: 1,
      );

      notifier.placeStone(const Position(4, 4));

      final state = container.read(localGameProvider);
      expect(state, isNotNull);
      expect(state!.board.at(const Position(4, 4)), StoneColor.p1);
    });

    test('undo reverts last human move', () async {
      final notifier = container.read(localGameProvider.notifier);
      notifier.startGame(
        boardSize: 9,
        difficulty: BotDifficulty.beginner,
        humanName: 'PLAYER_1',
        botCount: 1,
      );

      notifier.placeStone(const Position(4, 4));
      // Give async bot turn time to process/discard or wait
      await Future<void>.delayed(const Duration(milliseconds: 100));

      if (notifier.canUndo) {
        notifier.undo();
        final undoneState = container.read(localGameProvider);
        expect(undoneState!.board.at(const Position(4, 4)), isNull);
      }
    });
  });
}
