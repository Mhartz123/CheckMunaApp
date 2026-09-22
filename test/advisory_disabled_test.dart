import 'package:flutter_test/flutter_test.dart';
import 'package:ui_prototype/models/scan_record.dart';
import 'package:ui_prototype/services/compliance_engine.dart';
import 'package:ui_prototype/services/date_code_parser.dart';
import 'package:ui_prototype/services/fda_dataset_checker.dart';

/// The FDA advisory-list check is switched off until the dataset is cleaned
/// (see ComplianceEngine._advisoryDatasetEnabled). This pins that off: a name
/// the list DOES match — the dataset test proves it — must no longer turn a
/// scan into a Warning, and the verdict must fall to the remaining checks.
///
/// When the dataset is cleaned and the flag set back to true, this test is
/// expected to fail and should be deleted along with the flag.
const Map<PhotoSlot, String> _advisoryListedLabel = <PhotoSlot, String>{
  // Same text fda_dataset_checker_test proves the list matches.
  PhotoSlot.front: 'MIRACLE WHITE\nAdvance Whitening Capsules\n'
      'Food Supplement\nNet Wt. 500mg x 30 capsules',
  PhotoSlot.expiration: 'EXP 10/2028',
  PhotoSlot.ingredients: 'Glutathione, Vitamin C, Collagen, Kojic Acid',
};

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  test('the dataset itself still matches this label', () async {
    // Guards the test below: without this, it would pass vacuously if the
    // name simply stopped being on the list.
    await FdaDatasetChecker.ensureLoaded();
    expect(FdaDatasetChecker.match(_advisoryListedLabel.values.join('\n')),
        isNotNull);
  });

  test('a listed name no longer produces a Warning', () async {
    final record = await ComplianceEngine.analyzeLabel(
      textBySlot: _advisoryListedLabel,
      combinedText: _advisoryListedLabel.values.join('\n'),
      ocrConfidence: null,
      dateCode: DateCode(
        expiry: DateTime(2028, 10, 31),
        status: DateCodeStatus.parsed,
      ),
      packagingType: PackagingType.box,
    );

    expect(record.status, ComplianceStatus.compliant);
    expect(record.reasons.any((r) => r.contains('FDA')), isFalse);
  });

  test('the other checks still decide the verdict', () async {
    final record = await ComplianceEngine.analyzeLabel(
      textBySlot: _advisoryListedLabel,
      combinedText: _advisoryListedLabel.values.join('\n'),
      ocrConfidence: null,
      dateCode: DateCode(
        expiry: DateTime(2020, 1, 31),
        status: DateCodeStatus.parsed,
      ),
      packagingType: PackagingType.box,
    );

    // Expired: non-compliant, and not Warning.
    expect(record.status, ComplianceStatus.nonCompliant);
  });
}
