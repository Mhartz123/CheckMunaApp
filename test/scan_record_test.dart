import 'package:flutter_test/flutter_test.dart';
import 'package:ui_prototype/models/scan_record.dart';

/// A record's data.json is the only thing that survives an app restart, and
/// the same shape is what ReportService posts to the dashboard. So the kind
/// discriminator, the packaging type, and each half's fields all have to
/// round-trip exactly — a damage scan must not come back as a label scan, and
/// an inspection must keep both halves.
void main() {
  group('ScanRecord round-trip', () {
    test('label scan keeps its fields and carries no packaging type', () {
      final original = ScanRecord(
        kind: ScanKind.label,
        status: ComplianceStatus.nonCompliant,
        matchedKeyword: 'no ingredient list',
        reasons: const ['No ingredient list was detected on the label.'],
        productName: 'Vitamin C 500mg',
        expiration: '2027-05',
        ingredients: 'Ascorbic acid, magnesium stearate',
        extractedText: 'VITAMIN C 500MG\nEXP 2027-05',
        damageCheck: const DamageCheckResult.notPerformed(),
        scannedAt: DateTime.parse('2026-08-16T10:30:00.000'),
      );

      final restored = ScanRecord.fromJson(original.toJson());

      expect(restored.kind, ScanKind.label);
      expect(restored.hasLabelData, isTrue);
      expect(restored.hasDamageData, isFalse);
      expect(restored.productName, 'Vitamin C 500mg');
      expect(restored.expiration, '2027-05');
      expect(restored.reasons, original.reasons);
      expect(restored.scannedAt, original.scannedAt);
      // A label-only scan never picks a packaging type.
      expect(restored.packagingType, isNull);
      expect(restored.damageCheck.available, isFalse);
    });

    test('damage scan keeps packaging type and detections', () {
      final original = ScanRecord(
        kind: ScanKind.damage,
        status: ComplianceStatus.nonCompliant,
        matchedKeyword: 'packaging damage',
        reasons: const ['Packaging damage detected.'],
        productName: '—',
        expiration: '—',
        ingredients: '—',
        extractedText: '',
        packagingType: PackagingType.box,
        damageCheck: const DamageCheckResult(
          available: true,
          message: 'Possible packaging damage detected: Dent, Scratches.',
          isDamaged: true,
          detections: ['Dent', 'Dent', 'Scratches'],
          maxConfidence: 0.82,
        ),
        scannedAt: DateTime.parse('2026-08-16T11:00:00.000'),
      );

      final restored = ScanRecord.fromJson(original.toJson());

      expect(restored.kind, ScanKind.damage);
      expect(restored.hasDamageData, isTrue);
      expect(restored.hasLabelData, isFalse);
      expect(restored.packagingType, PackagingType.box);

      final damage = restored.damageCheck;
      expect(damage.available, isTrue);
      expect(damage.isDamaged, isTrue);
      // Order and repeats are preserved — two dents is not one dent.
      expect(damage.detections, ['Dent', 'Dent', 'Scratches']);
      expect(damage.maxConfidence, closeTo(0.82, 1e-9));
    });

    test('inspection scan keeps both halves in one record', () {
      final original = ScanRecord(
        kind: ScanKind.both,
        status: ComplianceStatus.banned,
        matchedKeyword: 'Lipo Slim Extreme',
        reasons: const ['Matches FDA advisory.', 'Packaging damage detected.'],
        productName: 'Lipo Slim Extreme',
        expiration: '2026-11-30',
        ingredients: 'Green tea extract, caffeine',
        extractedText: 'LIPO SLIM EXTREME',
        packagingType: PackagingType.bottle,
        damageCheck: const DamageCheckResult(
          available: true,
          message: 'Possible packaging damage detected: Scratches.',
          isDamaged: true,
          detections: ['Scratches'],
          maxConfidence: 0.51,
        ),
        scannedAt: DateTime.parse('2026-08-16T12:00:00.000'),
      );

      final restored = ScanRecord.fromJson(original.toJson());

      expect(restored.kind, ScanKind.both);
      // The whole point of the combined flow: neither half is dropped.
      expect(restored.hasLabelData, isTrue);
      expect(restored.hasDamageData, isTrue);
      expect(restored.productName, 'Lipo Slim Extreme');
      expect(restored.packagingType, PackagingType.bottle);
      expect(restored.damageCheck.detections, ['Scratches']);
      expect(restored.status, ComplianceStatus.banned);
      expect(restored.statusLabel, 'WARNING / BANNED');
    });
  });

  group('legacy records', () {
    test('a record saved before the split reads as both halves', () {
      // Pre-split data.json had no `kind` and carried label + damage
      // together; treating it as label-only would hide its damage result.
      final restored = ScanRecord.fromJson({
        'status': 'NON-COMPLIANT',
        'productName': 'Old Product',
        'expiration': '2025-01',
        'ingredients': 'Sugar, water',
        'scannedAt': '2026-06-01T10:00:00.000',
        'damageCheck': {
          'available': true,
          'message': 'No packaging damage detected.',
          'isDamaged': false,
          'detections': <String>[],
          'maxConfidence': 0.0,
        },
      });

      expect(restored.kind, ScanKind.both);
      expect(restored.hasLabelData, isTrue);
      expect(restored.hasDamageData, isTrue);
      expect(restored.packagingType, isNull);
    });

    test('an unrecognised kind falls back to both rather than throwing', () {
      final restored = ScanRecord.fromJson({
        'kind': 'something_else',
        'status': 'COMPLIANT',
        'scannedAt': '2026-06-01T10:00:00.000',
      });
      expect(restored.kind, ScanKind.both);
    });

    test('an unrecognised packaging type reads as null', () {
      final restored = ScanRecord.fromJson({
        'kind': 'damage',
        'packagingType': 'pouch',
        'status': 'COMPLIANT',
        'scannedAt': '2026-06-01T10:00:00.000',
      });
      expect(restored.packagingType, isNull);
    });
  });

  group('DamageCheckResult', () {
    test('notPerformed and placeholder are both unavailable, not clean', () {
      // "Couldn't run" must stay distinguishable from "ran and found
      // nothing", or clean-result counts get inflated.
      const notRun = DamageCheckResult.notPerformed();
      const placeholder = DamageCheckResult.placeholder();
      expect(notRun.available, isFalse);
      expect(notRun.isDamaged, isFalse);
      expect(placeholder.available, isFalse);

      const clean = DamageCheckResult(
        available: true,
        message: 'No packaging damage detected.',
      );
      expect(clean.available, isTrue);
      expect(clean.isDamaged, isFalse);
    });

    test('a null damageCheck deserialises to the placeholder', () {
      final restored = DamageCheckResult.fromJson(null);
      expect(restored.available, isFalse);
      expect(restored.detections, isEmpty);
    });
  });

  group('PackagingType', () {
    test('only box has a model wired up today', () {
      expect(PackagingType.box.hasModel, isTrue);
      expect(PackagingType.foil.hasModel, isFalse);
      expect(PackagingType.bottle.hasModel, isFalse);
    });

    test('labels are the user-facing names used across app and dashboard', () {
      expect(PackagingType.box.label, 'Box');
      expect(PackagingType.foil.label, 'Foil');
      expect(PackagingType.bottle.label, 'Bottle');
    });
  });
}
