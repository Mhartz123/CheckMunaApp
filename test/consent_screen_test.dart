import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_prototype/screens/consent_screen.dart';
import 'package:ui_prototype/services/app_prefs.dart';

void main() {
  late Directory tmp;
  final prefs = AppPrefs.instance;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('consent_screen_test');
    AppPrefs.debugDirectory = tmp;
    prefs.resetForTest();
  });

  tearDown(() {
    AppPrefs.debugDirectory = null;
    prefs.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester, VoidCallback onDecided) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ConsentScreen(onDecided: onDecided),
    ));
  }

  testWidgets('sharing cannot be agreed to without acknowledging the notice',
      (tester) async {
    var decided = false;
    await pump(tester, () => decided = true);

    final share = find.byKey(const ValueKey('consent-share'));
    expect(tester.widget<ElevatedButton>(share).onPressed, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(tester.widget<ElevatedButton>(share).onPressed, isNotNull);

    await tester.runAsync(() async {
      await tester.tap(share);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(decided, isTrue);
    expect(prefs.sharingAllowed, isTrue);
  });

  testWidgets('declining is always one tap and blocks sharing',
      (tester) async {
    var decided = false;
    await pump(tester, () => decided = true);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('consent-decline')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(decided, isTrue);
    expect(prefs.needsConsent, isFalse);
    expect(prefs.sharingAllowed, isFalse);
  });
}
