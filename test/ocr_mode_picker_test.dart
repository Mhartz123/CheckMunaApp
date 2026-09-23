import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_prototype/screens/camera_screen.dart';
import 'package:ui_prototype/screens/packaging_type_screen.dart';
import 'package:ui_prototype/services/app_prefs.dart';

/// The reading mode is the one control on this screen that changes how long a
/// scan takes, so it has to be offered where OCR actually runs and nowhere
/// else — and the choice has to stick.
void main() {
  late Directory tmp;
  final prefs = AppPrefs.instance;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ocr_mode_test');
    AppPrefs.debugDirectory = tmp;
    prefs.resetForTest();
  });

  tearDown(() {
    AppPrefs.debugDirectory = null;
    prefs.resetForTest();
    // The picker saves without awaiting, so on Windows the prefs file can
    // still be open when the test ends. The temp directory is the OS's to
    // reclaim; failing the test over it would only make this flaky.
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // ignore
    }
  });

  Future<void> pump(WidgetTester tester, CameraMode mode) async {
    await tester.pumpWidget(
      MaterialApp(home: PackagingTypeScreen(mode: mode)),
    );
    await tester.pump();
  }

  testWidgets('a label check offers both modes, Accurate selected', (t) async {
    await pump(t, CameraMode.label);

    expect(find.text('Reading mode'), findsOneWidget);
    expect(find.text('Accurate'), findsOneWidget);
    expect(find.text('Fast'), findsOneWidget);
    expect(find.text(OcrMode.accurate.description), findsOneWidget);
  });

  testWidgets('an inspection offers it too', (t) async {
    await pump(t, CameraMode.inspection);
    expect(find.text('Reading mode'), findsOneWidget);
  });

  testWidgets('a damage-only scan does not, since it reads no text', (t) async {
    await pump(t, CameraMode.damage);
    expect(find.text('Reading mode'), findsNothing);
  });

  testWidgets('picking Fast shows its description and is remembered',
      (t) async {
    await pump(t, CameraMode.label);

    await t.tap(find.text('Fast'));
    await t.pump();

    expect(find.text(OcrMode.fast.description), findsOneWidget);
    expect(prefs.ocrMode, OcrMode.fast);

    // The picker does not await the save, so let it land before the temp
    // directory is torn down underneath the open handle.
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
  });
}
