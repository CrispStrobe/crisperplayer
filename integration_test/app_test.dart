import 'package:crisperplayer/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('installed app starts with onboarding or library',
      (tester) async {
    await app.main();
    await tester.pumpAndSettle();
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.textContaining('could not start'), findsNothing);
    expect(find.byType(Scaffold), findsWidgets);
  });
}
