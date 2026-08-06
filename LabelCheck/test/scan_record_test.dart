import 'package:flutter_test/flutter_test.dart';
import 'package:ui_prototype/models/scan_record.dart';

/// A record's data.json is the only thing that survives an app restart, so the
/// type discriminator and each half's fields have to round-trip exactly — a
/// label record must not come back as a damage record, and vice versa.
void main() {
  group('ScanRecord round-trip', () {
    test('label record keeps its type and reported fields', () {
      final original = ScanRecord(
        type: ScanType.label,
        status: ComplianceStatus.nonCompliant,
        matchedKeyword: 'no ingredient list',
        reasons: const ['No ingredient list was detected on the label.'],
        productName: 'Vitamin C 500mg',
        expiration: '2027-05',
        ingredients: 'Ascorbic acid, magnesium stearate',
        allLabelsPresent: false,
        extractedText: 'VITAMIN C 500MG\nEXP 2027-05',
        damageCheck: const DamageCheckResult.placeholder(),
        scannedAt: DateTime.parse('2026-07-27T10:30:00.000'),
      );

      final restored = ScanRecord.fromJson(original.toJson());

      expect(restored.type, ScanType.label);
      expect(restored.isLabelCheck, isTrue);
      expect(restored.isDamageCheck, isFalse);
      expect(restored.productName, 'Vitamin C 500mg');
      expect(restored.expiration, '2027-05');
      expect(restored.allLabelsPresent, isFalse);
      expect(restored.status, ComplianceStatus.nonCompliant);
      expect(restored.reasons, original.reasons);
      expect(restored.scannedAt, original.scannedAt);
      // A label record carries no damage result.
      expect(restored.damageCheck.available, isFalse);
    });

    test('damage record keeps its per-side findings', () {
      final original = ScanRecord(
        type: ScanType.damage,
        status: ComplianceStatus.nonCompliant,
        matchedKeyword: 'Damage',
        reasons: const ['Front — Damage, 2 spots (78% confidence)'],
        productName: '—',
        expiration: '—',
        ingredients: '—',
        allLabelsPresent: false,
        extractedText: '',
        damageCheck: const DamageCheckResult(
          available: true,
          message: 'Packaging damage detected on: Front, Back.',
          isDamaged: true,
          findings: [
            DamageFinding(
              slot: BoxSlot.front,
              label: 'Damage',
              spotCount: 2,
              confidence: 0.78,
            ),
            DamageFinding(
              slot: BoxSlot.back,
              label: 'Damage',
              spotCount: 1,
              confidence: 0.55,
            ),
          ],
          maxConfidence: 0.78,
        ),
        scannedAt: DateTime.parse('2026-07-27T11:00:00.000'),
      );

      final restored = ScanRecord.fromJson(original.toJson());

      expect(restored.type, ScanType.damage);
      expect(restored.isDamageCheck, isTrue);

      final damage = restored.damageCheck;
      expect(damage.available, isTrue);
      expect(damage.isDamaged, isTrue);
      expect(damage.findings, hasLength(2));
      expect(damage.findings.first.slot, BoxSlot.front);
      expect(damage.findings.first.spotCount, 2);
      expect(damage.findings.first.confidence, closeTo(0.78, 1e-9));
      expect(damage.findings.last.slot, BoxSlot.back);
      expect(damage.totalSpots, 3);
      expect(damage.affectedSides, 'Front, Back');
      expect(damage.damageTypes, ['Damage']);
    });

    test('a findings entry with an unknown slot is dropped, not fatal', () {
      final restored = DamageCheckResult.fromJson({
        'available': true,
        'message': 'Packaging damage detected on: Front.',
        'isDamaged': true,
        'maxConfidence': 0.6,
        'findings': [
          {'slot': 'box_front', 'label': 'Damage', 'spotCount': 1, 'confidence': 0.6},
          {'slot': 'box_lid', 'label': 'Damage', 'spotCount': 1, 'confidence': 0.9},
        ],
      });

      expect(restored.findings, hasLength(1));
      expect(restored.findings.single.slot, BoxSlot.front);
    });
  });

  group('ScanType', () {
    test('ids round-trip', () {
      expect(ScanTypeX.fromId(ScanType.label.id), ScanType.label);
      expect(ScanTypeX.fromId(ScanType.damage.id), ScanType.damage);
    });

    test('an unrecognised or absent scanType reads as a label check', () {
      // Damage is the newer, narrower record shape — defaulting an unknown
      // discriminator to it would put blank rows in the damage report.
      expect(ScanTypeX.fromId(null), ScanType.label);
      expect(ScanTypeX.fromId('SOMETHING_ELSE'), ScanType.label);
    });
  });

  group('damage presentation', () {
    ScanRecord damageRecordWith(DamageCheckResult damage) => ScanRecord(
          type: ScanType.damage,
          status: damage.isDamaged
              ? ComplianceStatus.nonCompliant
              : ComplianceStatus.compliant,
          matchedKeyword: '—',
          reasons: const [],
          productName: '—',
          expiration: '—',
          ingredients: '—',
          allLabelsPresent: false,
          extractedText: '',
          damageCheck: damage,
          scannedAt: DateTime.parse('2026-07-27T12:00:00.000'),
        );

    test('an unavailable check reads as unavailable, not as clean', () {
      final record =
          damageRecordWith(const DamageCheckResult.placeholder());
      expect(record.damageTitle, 'Check unavailable');
    });

    test('a clean check reads as no damage', () {
      final record = damageRecordWith(const DamageCheckResult(
        available: true,
        message: 'No packaging damage detected on any side.',
      ));
      expect(record.damageTitle, 'No damage detected');
    });

    test('finding summary names the side, count and confidence', () {
      const finding = DamageFinding(
        slot: BoxSlot.side1,
        label: 'Damage',
        spotCount: 1,
        confidence: 0.62,
      );
      expect(finding.summary, 'Side 1 — Damage, 1 spot (62% confidence)');
    });
  });
}
