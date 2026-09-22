import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_prototype/models/damage_report.dart';
import 'package:ui_prototype/models/scan_record.dart';
import 'package:ui_prototype/widgets/damage_report_view.dart';

/// The report is a dense table inside a scrolling column on two screens, and
/// it is the only place the per-photo figures are ever shown. So: it must
/// vanish entirely when no report was captured, it must name every photo
/// (including one that failed), and it must lay out at phone width without
/// overflowing — the numbers are worthless if a column is clipped.
DamageDetection _det(String label, double confidence, {int source = 0}) =>
    DamageDetection(
      label: label,
      confidence: confidence,
      left: 0.1,
      top: 0.1,
      width: 0.2,
      height: 0.2,
      sourceIndex: source,
    );

DamageSessionReport _report() => DamageSessionReport(
      subject: 'box',
      modelAsset: 'assets/box_damage_yolo11n_int8.onnx',
      inputSize: 416,
      confThreshold: 0.35,
      modelLoadMs: 284,
      photos: [
        DamagePhotoReport(
          index: 0,
          label: 'Front',
          preprocessMs: 38,
          inferenceMs: 121,
          succeeded: true,
          detections: [_det('Structural deformation', 0.82)],
        ),
        const DamagePhotoReport(
          index: 1,
          label: 'Side',
          preprocessMs: 31,
          inferenceMs: 96,
          succeeded: true,
        ),
        DamagePhotoReport(
          index: 2,
          label: 'Other side',
          preprocessMs: 44,
          inferenceMs: 133,
          succeeded: true,
          detections: [_det('Label aberration', 0.51, source: 2)],
        ),
        const DamagePhotoReport(
          index: 3,
          label: 'Back',
          preprocessMs: 0,
          inferenceMs: 0,
          succeeded: false,
        ),
      ],
    );

void main() {
  Future<void> pump(WidgetTester tester, DamageSessionReport? report,
      {Size size = const Size(360, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DamageReportView(
            report: report,
            failThreshold: 0.70,
            initiallyExpanded: true,
          ),
        ),
      ),
    ));
  }

  testWidgets('renders nothing when no report was captured', (tester) async {
    await pump(tester, null);
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('names every photo, including the one that failed',
      (tester) async {
    await pump(tester, _report());

    expect(find.text('Front'), findsOneWidget);
    expect(find.text('Side'), findsOneWidget);
    expect(find.text('Other side'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    // A failed photo reads as a failure, never as a clean result.
    expect(find.text('fail'), findsOneWidget);
    expect(find.text('clean'), findsOneWidget);
  });

  testWidgets('reports per-image and session inference time', (tester) async {
    await pump(tester, _report());

    // Per photo, unaggregated.
    expect(find.text('121 ms'), findsOneWidget);
    expect(find.text('133 ms'), findsOneWidget);
    // Session: 121 + 96 + 133 = 350 total over the three photos that ran.
    expect(find.text('350 ms'), findsOneWidget);
    expect(find.text('96.0 ms–133 ms'), findsOneWidget);
    expect(find.text('3 of 4  (1 failed)'), findsOneWidget);
  });

  testWidgets('reports confidence per class', (tester) async {
    await pump(tester, _report());

    expect(find.text('Structural deformation'), findsOneWidget);
    expect(find.text('Label aberration'), findsOneWidget);
    expect(find.text('82%'), findsWidgets);
    expect(find.text('51%'), findsWidgets);
  });

  testWidgets('lays out at phone width without overflowing', (tester) async {
    await pump(tester, _report(), size: const Size(320, 900));
    expect(tester.takeException(), isNull);
  });
}
