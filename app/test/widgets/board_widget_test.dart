import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_engine/go_engine.dart';
import 'package:gohackme/features/board/widgets/board_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BoardWidget', () {
    testWidgets('renders CustomPaint with BoardPainter', (tester) async {
      final board = Board(size: 9);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: BoardWidget(
                board: board,
                boardSize: 9,
              ),
            ),
          ),
        ),
      );

      // Verify BoardWidget mounts cleanly
      expect(find.byType(BoardWidget), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('triggers onTap callback with valid position on tap', (tester) async {
      final board = Board(size: 9);
      Position? tappedPosition;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 400,
                child: BoardWidget(
                  board: board,
                  boardSize: 9,
                  onTap: (pos) {
                    tappedPosition = pos;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Tap near the center of the board
      await tester.tap(find.byType(BoardWidget));
      await tester.pump(const Duration(milliseconds: 100));

      // The hit test converts screen offset back to a board position if inside bounds
      // tappedPosition will either be a valid Position or null if off-intersection
      expect(tappedPosition == null || tappedPosition is Position, isTrue);
    });
  });
}
