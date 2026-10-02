import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_prototype/models/scan_record.dart';
import 'package:ui_prototype/screens/camera_screen.dart';
import 'package:ui_prototype/screens/packaging_type_screen.dart';
import 'package:ui_prototype/services/app_prefs.dart';

/// Picking Box for a flow that photographs the packaging has to ask for the
/// box's shape before the camera opens — the side-panel steps are worded
/// from it.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('box_form_test');
    AppPrefs.debugDirectory = tmp;
    AppPrefs.instance.resetForTest();
  });

  tearDown(() {
    AppPrefs.debugDirectory = null;
    AppPrefs.instance.resetForTest();
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // The picker saves without awaiting; see ocr_mode_picker_test.
    }
  });

  Future<void> tapBox(WidgetTester tester, CameraMode mode) async {
    await tester.pumpWidget(MaterialApp(home: PackagingTypeScreen(mode: mode)));
    await tester.pump();
    await tester.tap(find.text(PackagingType.box.label).first);
    await tester.pumpAndSettle();
  }

  for (final mode in const [CameraMode.damage, CameraMode.inspection]) {
    testWidgets('${mode.name}: Box asks for the shape', (tester) async {
      await tapBox(tester, mode);

      expect(find.text('What shape is the box?'), findsOneWidget);
      for (final form in BoxForm.values) {
        expect(find.text(form.label), findsOneWidget);
      }
    });
  }

  testWidgets('dismissing the shape sheet stays on the picker', (tester) async {
    await tapBox(tester, CameraMode.damage);
    await tester.tapAt(const Offset(10, 10)); // the barrier above the sheet
    await tester.pumpAndSettle();

    expect(find.text('What shape is the box?'), findsNothing);
    expect(find.byType(PackagingTypeScreen), findsOneWidget);
    expect(find.byType(CameraScreen), findsNothing);
  });
}
