import 'package:flutter_test/flutter_test.dart';
import 'package:ui_prototype/models/scan_record.dart';
import 'package:ui_prototype/services/compliance_engine.dart';
import 'package:ui_prototype/services/date_code_parser.dart';

/// The FDA advisory check through the engine: a listed name on the front
/// panel turns the scan into a Warning, and nothing else does.
Future<ScanRecord> _analyze(Map<PhotoSlot, String> textBySlot) {
  return ComplianceEngine.analyzeLabel(
    textBySlot: textBySlot,
    combinedText: textBySlot.values.join('\n'),
    ocrConfidence: null,
    dateCode: DateCode(
      expiry: DateTime(2099, 10, 31),
      status: DateCodeStatus.parsed,
    ),
    packagingType: PackagingType.box,
  );
}

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  test('a listed name on the front panel is a Warning', () async {
    final record = await _analyze(const {
      PhotoSlot.front: 'OTC\nDezhong Zaoren Anshen Jiaonang\n24 capsules',
      PhotoSlot.expiration: 'EXP 10/2099',
      PhotoSlot.ingredients: 'Ingredients: Semen Ziziphi Spinosae, Poria',
    });

    expect(record.status, ComplianceStatus.warning);
    expect(record.reasons.first, contains('FDA Advisory No. 2021-1044'));
  });

  test('the same words outside the front panel do not match', () async {
    // The ingredient panel is generic words by nature; the name match reads
    // the front panel only.
    final record = await _analyze(const {
      PhotoSlot.front: 'SLEEPWELL\nHerbal Capsules',
      PhotoSlot.expiration: 'EXP 10/2099',
      PhotoSlot.ingredients:
          'Ingredients: Dezhong Zaoren Anshen extract, Poria',
    });

    expect(record.status, ComplianceStatus.compliant);
  });

  test('a generic name shared with a listed one stays compliant', () async {
    // "Tetracycline Tablets" is on the advisory CSV word for word.
    final record = await _analyze(const {
      PhotoSlot.front: 'Tetracycline Tablets\n250 mg',
      PhotoSlot.expiration: 'EXP 10/2099',
      PhotoSlot.ingredients: 'Each tablet contains Tetracycline HCl 250 mg',
    });

    expect(record.status, ComplianceStatus.compliant);
    expect(record.reasons.any((r) => r.contains('FDA')), isFalse);
  });

  test('the other checks still decide a non-listed product', () async {
    final record = await ComplianceEngine.analyzeLabel(
      textBySlot: const {
        PhotoSlot.front: 'Tetracycline Tablets',
        PhotoSlot.expiration: 'EXP 01/2020',
        PhotoSlot.ingredients: 'Tetracycline HCl 250 mg',
      },
      combinedText: 'Tetracycline Tablets\nEXP 01/2020\nTetracycline HCl',
      ocrConfidence: null,
      dateCode: DateCode(
        expiry: DateTime(2020, 1, 31),
        status: DateCodeStatus.parsed,
      ),
      packagingType: PackagingType.box,
    );

    expect(record.status, ComplianceStatus.nonCompliant);
  });
}
