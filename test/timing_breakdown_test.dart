import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_prototype/models/scan_timings.dart';
import 'package:ui_prototype/widgets/timing_breakdown.dart';

/// The breakdown is inside a scrolling column on two screens, and it is the
/// only place a reader ever sees these numbers. So: it must vanish entirely
/// when nothing was measured (rather than showing a table of zeros), and when
/// it does render it has to show the per-run mean, not just a total that looks
/// alarmingly large because four photos were summed.
void main() {
  Future<void> pump(WidgetTester tester, ScanTimings timings,
      {bool expanded = true}) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TimingBreakdown(
            timings: timings,
            initiallyExpanded: expanded,
          ),
        ),
      ),
    ));
  }

  testWidgets('renders nothing at all when nothing was measured',
      (tester) async {
    await pump(tester, ScanTimings.empty);

    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.textContaining('ms'), findsNothing);
  });

  testWidgets('shows the scan total, group subtotals and per-run means',
      (tester) async {
    await pump(
      tester,
      (ScanTimingsBuilder()
            ..add(TimingGroup.ocr, 'Product name recognition', 240, runs: 2)
            ..add(TimingGroup.damageModel, 'Inference', 320, runs: 4))
          .build(),
    );

    // Scan total, in the always-visible header.
    expect(find.textContaining('560 ms'), findsOneWidget);

    // Both group headings, each with its own subtotal.
    expect(find.text('Text recognition (ML Kit)'), findsOneWidget);
    expect(find.text('Damage model (YOLO, ONNX)'), findsOneWidget);
    expect(find.text('240 ms'), findsOneWidget);
    expect(find.text('320 ms'), findsOneWidget);

    // Run counts and the mean alongside the total, so four photos summing to
    // 320 ms cannot be misread as one 320 ms inference.
    expect(find.text('Product name recognition (×2)'), findsOneWidget);
    expect(find.text('Inference (×4)'), findsOneWidget);
    expect(find.text('320 ms  ·  80.0 ms each'), findsOneWidget);
  });

  testWidgets('a single-run stage shows one figure, with no mean', (tester) async {
    await pump(
      tester,
      (ScanTimingsBuilder()
            ..add(TimingGroup.damageModel, 'foil model load (one-time)', 480))
          .build(),
    );

    expect(find.text('foil model load (one-time)'), findsOneWidget);
    expect(find.textContaining('each'), findsNothing);
  });

  testWidgets('collapsed, it shows only the header total', (tester) async {
    await pump(
      tester,
      (ScanTimingsBuilder()..add(TimingGroup.ocr, 'Recognition', 150)).build(),
      expanded: false,
    );

    expect(find.text('PROCESSING TIME'), findsOneWidget);
    expect(find.textContaining('150 ms of on-device ML work'), findsOneWidget);
    expect(find.text('Text recognition (ML Kit)'), findsNothing);
  });
}
