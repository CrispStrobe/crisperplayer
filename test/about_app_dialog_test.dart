import 'package:crisperplayer/services/native_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:crisperplayer/widgets/about_app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'license registry loads shipped project and native license assets',
    () async {
      addTearDown(LicenseRegistry.reset);
      registerNativeLicenses();
      final entries = await LicenseRegistry.licenses.toList();
      final names = entries.expand((entry) => entry.packages).toSet();
      expect(
        names,
        containsAll([
          'CrisperPlayer',
          'libsmb2',
          'SQLite',
          'GNU LGPL 2.1',
          'GNU LGPL 3.0',
        ]),
      );
      final own = entries.firstWhere(
        (entry) => entry.packages.contains('CrisperPlayer'),
      );
      expect(
        own.paragraphs.map((paragraph) => paragraph.text).join(' '),
        contains('AFFERO GENERAL PUBLIC LICENSE'),
      );
    },
  );

  testWidgets('About uses package version and remains usable at 200% text', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'CrisperPlayer',
      packageName: 'com.crispstrobe.crisperplayer',
      version: '9.8.7',
      buildNumber: '456',
      buildSignature: '',
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppAboutDialog(context),
              child: const Text('About'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('Version 9.8.7 (456)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('View licenses'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('View licenses'));
    await tester.pumpAndSettle();
    expect(find.text('CrisperPlayer'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('About CrisperPlayer'), findsNothing);
  });
}
