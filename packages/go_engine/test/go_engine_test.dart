import 'package:go_engine/go_engine.dart';
import 'package:test/test.dart';

void main() {
  group('GameEngine Attack Integration', () {
    late GameState state;

    setUp(() {
      state = GameState.newGame(
        players: [
          const Player(id: 'p1', displayName: 'Alice'),
          const Player(id: 'p2', displayName: 'Bob'),
        ],
        boardSize: 9,
        initialSubnets: 10,
      );
    });

    test('PATCH attack adds shield stack and deflects incoming attack', () {
      // p1 launches PATCH
      final patchResult = GameEngine.launchAttack(
        state,
        const AttackAction(
          type: AttackType.patch,
          attackerPlayerId: 'p1',
          targetPlayerId: 'p1',
        ),
      );
      expect(patchResult, isA<ActionSuccess>());
      final patchedState = (patchResult as ActionSuccess).newState;
      expect(patchedState.patchShields['p1'], 1);
      // Cost of patch is 3
      expect(patchedState.subnetsOf('p1'), 7);

      // p1 passes to p2 turn
      final passResult = GameEngine.pass(patchedState, 'p1') as ActionSuccess;

      // p2 launches DDOS against p1
      final attackResult = GameEngine.launchAttack(
        passResult.newState,
        const AttackAction(
          type: AttackType.ddos,
          attackerPlayerId: 'p2',
          targetPlayerId: 'p1',
        ),
      );
      expect(attackResult, isA<ActionSuccess>());
      final finalSuccess = attackResult as ActionSuccess;
      // Attack was deflected by PATCH
      expect(finalSuccess.event, isA<AttackLaunchedEvent>());
      final evt = finalSuccess.event as AttackLaunchedEvent;
      expect(evt.wasBlocked, isTrue);
      // p1 patch shield count decremented back to 0
      expect(finalSuccess.newState.patchShields['p1'], 0);
      // DDOS effect was NOT applied
      expect(finalSuccess.newState.hasEffect('p1', AttackType.ddos), isFalse);
    });

    test('TROJAN attack steals subnets from target', () {
      // Give p2 20 subnets
      final richState = state.copyWith(
        subnets: {'p1': 10, 'p2': 20},
      );

      final result = GameEngine.launchAttack(
        richState,
        const AttackAction(
          type: AttackType.trojan,
          attackerPlayerId: 'p1',
          targetPlayerId: 'p2',
        ),
      );
      expect(result, isA<ActionSuccess>());
      final newState = (result as ActionSuccess).newState;
      // Trojan cost = 5. p1 has 10 - 5 = 5. Steals half of 20 = 10. p1 total = 15.
      expect(newState.subnetsOf('p1'), 15);
      expect(newState.subnetsOf('p2'), 10);
    });

    test('WORM attack overwrites enemy stone at position', () {
      // p1 places stone at (4,4)
      final p1Move = GameEngine.placeStone(state, 'p1', const Position(4, 4)) as ActionSuccess;
      // p2 has subnets
      final p2Turn = p1Move.newState.copyWith(subnets: {'p1': 5, 'p2': 10});

      // p2 launches WORM to overwrite p1's stone at (4,4)
      final wormResult = GameEngine.launchAttack(
        p2Turn,
        const AttackAction(
          type: AttackType.worm,
          attackerPlayerId: 'p2',
          targetPlayerId: 'p1',
          targetPosition: Position(4, 4),
        ),
      );
      expect(wormResult, isA<ActionSuccess>());
      final newState = (wormResult as ActionSuccess).newState;
      expect(newState.board.at(const Position(4, 4)), StoneColor.p2);
    });

    test('KNIGHTS_EYE plants a trap effect', () {
      final result = GameEngine.launchAttack(
        state,
        const AttackAction(
          type: AttackType.knightseye,
          attackerPlayerId: 'p1',
          targetPlayerId: 'p1',
          targetPosition: Position(2, 2),
        ),
      );
      expect(result, isA<ActionSuccess>());
      final newState = (result as ActionSuccess).newState;
      expect(newState.board.at(const Position(2, 2)), StoneColor.p1);
      expect(AttackSystem.isHoneypot(newState, const Position(2, 2), 'p1'), isTrue);
    });
  });
}
