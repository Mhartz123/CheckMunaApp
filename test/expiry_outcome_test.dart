import 'package:flutter_test/flutter_test.dart';
import 'package:ui_prototype/models/scan_record.dart';
import 'package:ui_prototype/services/compliance_engine.dart';
import 'package:ui_prototype/services/date_code_parser.dart';
import 'package:ui_prototype/services/fda_dataset_checker.dart';

/// An ordinary label that trips none of the other checks, so the expiry
/// outcome is the only thing deciding the verdict.
const Map<PhotoSlot, String> _label = <PhotoSlot, String>{
  PhotoSlot.front: 'Pedzinc Multivitamins Syrup',
  PhotoSlot.expiration: 'P009122 10/2028 10/2025',
  PhotoSlot.ingredients:
      'Each 5 mL contains Zinc Sulfate Monohydrate equivalent to elemental zinc',
};

Future<ScanRecord> _analyze(DateCode? dateCode) => ComplianceEngine.analyzeLabel(
      textBySlot: _label,
      combinedText: _label.values.join('\n'),
      // Null keeps the semantic tier from firing, so no ONNX model is loaded.
      ocrConfidence: null,
      dateCode: dateCode,
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FdaDatasetChecker.ensureLoaded();
  });

  test('a readable, in-date code passes', () async {
    final record = await _analyze(DateCode(
      manufactured: DateTime(2025, 10, 1),
      expiry: DateTime(2028, 10, 31),
      batch: 'P009122',
      status: DateCodeStatus.parsed,
    ));

    expect(record.status, ComplianceStatus.compliant);
    expect(record.expiration, '2028-10');
  });

  test('an unreadable code fails the scan instead of passing silently',
      () async {
    final record = await _analyze(const DateCode(
      status: DateCodeStatus.unreadable,
      note: 'No readable date code found.',
    ));

    // This is the whole point of the unreadable outcome. Before it existed, a
    // code that could not be read left expirationDate null, which made
    // expired=false, which let the scan through as if the expiry were fine.
    expect(record.status, ComplianceStatus.nonCompliant);
    expect(record.expiration, 'Unreadable');
    expect(
      record.reasons.any((r) => r.contains('could not be read')),
      isTrue,
      reason: 'the report has to say why, not just fail',
    );
  });

  test('an expired code still fails', () async {
    final record = await _analyze(DateCode(
      manufactured: DateTime(2020, 1, 1),
      expiry: DateTime(2021, 1, 31),
      status: DateCodeStatus.parsed,
    ));

    expect(record.status, ComplianceStatus.nonCompliant);
    expect(record.reasons.any((r) => r.contains('Expired')), isTrue);
  });

  test('an ambiguous but valid code is reported, not rejected', () async {
    final record = await _analyze(DateCode(
      expiry: DateTime(2028, 10, 31),
      status: DateCodeStatus.ambiguous,
      note: 'Single unlabelled date read; assumed to be the expiry.',
    ));

    expect(record.status, ComplianceStatus.compliant);
    expect(record.expiration, '2028-10');
  });

  test('without a structured read it falls back to the old string parser',
      () async {
    final record = await _analyze(null);

    // The expiration slot text carries 10/2028, which LabelParser finds.
    expect(record.status, ComplianceStatus.compliant);
    expect(record.expiration, isNot('Unreadable'));
  });
}
