import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gohackme/features/board/widgets/codex/attack_codex_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AttackCodex Widget', () {
    testWidgets('renders luminous AttackCodex button with icon and title', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AttackCodex(),
            ),
          ),
        ),
      );

      expect(find.text('// ATTACK_CODEX'), findsOneWidget);
      expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
    });

    testWidgets('tapping AttackCodex opens fullscreen dialog showing attack cards', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AttackCodex(),
            ),
          ),
        ),
      );

      // Tap the Attack Codex button
      await tester.tap(find.text('// ATTACK_CODEX'));
      await tester.pumpAndSettle();

      // Verify the dialog header and attack entries are rendered
      expect(find.text('[X]'), findsOneWidget);
      expect(find.textContaining('BACKDOOR'), findsWidgets);
      expect(find.textContaining('WORM'), findsWidgets);
      expect(find.textContaining('TROJAN'), findsWidgets);

      // Tap [X] to close the dialog
      await tester.tap(find.text('[X]'));
      await tester.pumpAndSettle();

      // Verify dialog is closed
      expect(find.text('[X]'), findsNothing);
    });
  });
}
