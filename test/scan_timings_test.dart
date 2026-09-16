import 'package:flutter_test/flutter_test.dart';
import 'package:ui_prototype/models/scan_record.dart';
import 'package:ui_prototype/models/scan_timings.dart';

/// Timings are a measurement, and a measurement that silently turns into 0 is
/// worse than no measurement at all — it would be quoted as "0 ms of OCR" in
/// the evaluation. So the cases that matter here are: repeated stages
/// accumulate instead of overwriting each other, an absent measurement stays
/// absent through a save/load cycle, and a present one comes back unchanged.
void main() {
  group('ScanTimingsBuilder', () {
    test('repeating a stage sums the time and counts the runs', () {
      final builder = ScanTimingsBuilder()
        ..add(TimingGroup.damageModel, 'Inference', 80)
        ..add(TimingGroup.damageModel, 'Inference', 100)
        ..add(TimingGroup.damageModel, 'Inference', 120);

      final timings = builder.build();
      expect(timings.stages, hasLength(1));
      expect(timings.stages.single.totalMs, 300);
      expect(timings.stages.single.runs, 3);
      expect(timings.stages.single.meanMs, 100);
    });

    test('same label in different groups stays two separate stages', () {
      final timings = (ScanTimingsBuilder()
            ..add(TimingGroup.ocr, 'Preprocessing', 40)
            ..add(TimingGroup.damageModel, 'Preprocessing', 900))
          .build();

      expect(timings.stages, hasLength(2));
      expect(timings.totalMsIn(TimingGroup.ocr), 40);
      expect(timings.totalMsIn(TimingGroup.damageModel), 900);
      expect(timings.totalMs, 940);
      expect(timings.groups,
          [TimingGroup.ocr, TimingGroup.damageModel]);
    });

    test('a single-run stage reports its total as its mean', () {
      final timings =
          (ScanTimingsBuilder()..add(TimingGroup.damageModel, 'Model load', 512))
              .build();
      expect(timings.stages.single.meanMs, 512);
    });

    test('groups lists only the groups actually measured', () {
      final timings =
          (ScanTimingsBuilder()..add(TimingGroup.ocr, 'Recognition', 30))
              .build();
      expect(timings.groups, [TimingGroup.ocr]);
      expect(timings.totalMsIn(TimingGroup.damageModel), 0);
      expect(timings.stagesIn(TimingGroup.damageModel), isEmpty);
    });

    test('an empty builder builds the empty timings, not a zero row', () {
      expect(ScanTimingsBuilder().build().isEmpty, isTrue);
      expect(ScanTimings.empty.stages, isEmpty);
      expect(ScanTimings.empty.totalMs, 0);
    });
  });

  group('ScanTimings round-trip', () {
    test('stages survive JSON with group, runs and total intact', () {
      final original = (ScanTimingsBuilder()
            ..add(TimingGroup.ocr, 'Product name recognition', 210, runs: 2)
            ..add(TimingGroup.damageModel, 'Inference', 340, runs: 4))
          .build();

      final restored = ScanTimings.fromJson(original.toJson());

      expect(restored.stages, hasLength(2));
      expect(restored.stages[0].group, TimingGroup.ocr);
      expect(restored.stages[0].label, 'Product name recognition');
      expect(restored.stages[0].totalMs, 210);
      expect(restored.stages[0].runs, 2);
      expect(restored.stages[1].group, TimingGroup.damageModel);
      expect(restored.stages[1].meanMs, 85);
      expect(restored.totalMs, 550);
    });

    test('a null or empty list deserialises to empty, never to a zero row', () {
      expect(ScanTimings.fromJson(null).isEmpty, isTrue);
      expect(ScanTimings.fromJson(const []).isEmpty, isTrue);
    });

    test('a malformed stage is dropped rather than read as 0 ms', () {
      final restored = ScanTimings.fromJson([
        {'group': 'ocr', 'label': 'Recognition', 'totalMs': 12.5, 'runs': 1},
        {'group': 'ocr', 'label': 'No time recorded'},
        'not a map',
      ]);

      expect(restored.stages, hasLength(1));
      expect(restored.stages.single.totalMs, 12.5);
    });
  });

  group('records carry their timings', () {
    test('a scan record round-trips its timings', () {
      final timings = (ScanTimingsBuilder()
            ..add(TimingGroup.ocr, 'Expiration date recognition', 96, runs: 2))
          .build();

      final restored = ScanRecord.fromJson(ScanRecord(
        kind: ScanKind.label,
        status: ComplianceStatus.compliant,
        matchedKeyword: '—',
        reasons: const [],
        productName: 'Vitamin C',
        expiration: '2027-05',
        ingredients: 'Ascorbic acid',
        extractedText: 'VITAMIN C',
        damageCheck: const DamageCheckResult.notPerformed(),
        timings: timings,
        scannedAt: DateTime.now(),
      ).toJson());

      expect(restored.timings.stages.single.label,
          'Expiration date recognition');
      expect(restored.timings.stages.single.runs, 2);
      expect(restored.timings.totalMs, 96);
    });

    test('a damage result round-trips its own model timings', () {
      final restored = DamageCheckResult.fromJson(DamageCheckResult(
        available: true,
        message: 'No packaging damage detected.',
        timings: (ScanTimingsBuilder()
              ..add(TimingGroup.damageModel, 'foil model load (one-time)', 480)
              ..add(TimingGroup.damageModel, 'Inference', 320, runs: 4))
            .build(),
      ).toJson());

      expect(restored.timings.stages, hasLength(2));
      expect(restored.timings.totalMsIn(TimingGroup.damageModel), 800);
    });

    test('records saved before timings existed load with none', () {
      final legacy = ScanRecord.fromJson({
        'kind': 'label',
        'status': 'COMPLIANT',
        'productName': 'Vitamin C',
        'scannedAt': DateTime.now().toIso8601String(),
      });

      expect(legacy.timings.isEmpty, isTrue);
      expect(legacy.damageCheck.timings.isEmpty, isTrue);
      // And an un-measured record must not write an empty key back out.
      expect(legacy.toJson().containsKey('timings'), isFalse);
    });
  });

  group('formatMs', () {
    test('sub-100 ms keeps one decimal, so 12.4 ms is not shown as 12', () {
      expect(formatMs(12.44), '12.4 ms');
      expect(formatMs(99.9), '99.9 ms');
    });

    test('100 ms and up rounds to whole milliseconds', () {
      expect(formatMs(100), '100 ms');
      expect(formatMs(847.6), '848 ms');
    });

    test('a second or more switches to seconds', () {
      expect(formatMs(1000), '1.00 s');
      expect(formatMs(12184), '12.18 s');
    });
  });
}
