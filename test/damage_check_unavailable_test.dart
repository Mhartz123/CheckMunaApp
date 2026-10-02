import 'package:flutter_test/flutter_test.dart';
import 'package:ui_prototype/models/damage_report.dart';
import 'package:ui_prototype/models/scan_record.dart';
import 'package:ui_prototype/services/compliance_engine.dart';
import 'package:ui_prototype/services/date_code_parser.dart';
import 'package:ui_prototype/services/fda_dataset_checker.dart';
import 'package:ui_prototype/services/packaging_damage_service.dart';

/// A damage check that could not look at the packaging has nothing to say
/// about it. It used to come back as compliant — a clean result nobody earned
/// — so these pin that it is now refused outright, in both flows that include
/// a damage step, and that a real finding is still reported.

/// Returns whatever result it was built with, standing in for the model.
class _FakeDetector extends PackagingDamageDetector {
  final DamageCheckResult result;

  _FakeDetector(this.result);

  @override
  Future<DamageCheckResult> check(List<String> photoPaths,
          {List<String>? photoLabels}) async =>
      result;
}

DamagePhotoReport _photo(int index, {required bool succeeded}) =>
    DamagePhotoReport(
      index: index,
      label: 'Photo ${index + 1}',
      preprocessMs: 0,
      inferenceMs: 0,
      succeeded: succeeded,
    );

DamageSessionReport _report(List<DamagePhotoReport> photos) =>
    DamageSessionReport(
      subject: 'box',
      modelAsset: 'assets/box_damage_yolo11n_640_int8.onnx',
      inputSize: 640,
      confThreshold: 0.25,
      photos: photos,
    );

/// A box label with nothing wrong with it, so only the damage side can decide.
const Map<PhotoSlot, String> _cleanLabel = <PhotoSlot, String>{
  PhotoSlot.front: 'Kremil-S',
  PhotoSlot.expiration: 'EXP 10/2028',
  PhotoSlot.ingredients: 'Ingredients: aluminum hydroxide, simeticone',
};

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FdaDatasetChecker.ensureLoaded();
  });

  tearDown(() =>
      PackagingDamageService.register(PackagingType.box, BoxDamageDetector()));

  void useDetector(DamageCheckResult result) => PackagingDamageService.register(
      PackagingType.box, _FakeDetector(result));

  Future<ScanRecord> damageScan() => ComplianceEngine.analyzeDamage(
        packagingType: PackagingType.box,
        boxPhotoPaths: const ['front.jpg', 'back.jpg'],
      );

  Future<ScanRecord> inspection() => ComplianceEngine.analyzeInspection(
        textBySlot: _cleanLabel,
        combinedText: _cleanLabel.values.join('\n'),
        packagingType: PackagingType.box,
        boxPhotoPaths: const ['front.jpg', 'back.jpg'],
        dateCode: DateCode(
          expiry: DateTime(2028, 10, 31),
          status: DateCodeStatus.parsed,
        ),
      );

  group('a check that could not run gives no verdict', () {
    const unavailable = DamageCheckResult(
      available: false,
      message: 'Damage check unavailable (model failed to load).',
    );

    test('a damage scan is refused, with the reason', () async {
      useDetector(unavailable);
      await expectLater(
        damageScan(),
        throwsA(isA<DamageCheckUnavailable>().having(
            (e) => e.message, 'message', contains('model failed to load'))),
      );
    });

    test('an inspection is refused even though its label is fine', () async {
      useDetector(unavailable);
      await expectLater(inspection(), throwsA(isA<DamageCheckUnavailable>()));
    });

    test('a scan with no packaging photos is refused', () async {
      // The real detector, which reports "no photos" before loading a model.
      await expectLater(
        ComplianceEngine.analyzeDamage(
          packagingType: PackagingType.box,
          boxPhotoPaths: const <String>[],
        ),
        throwsA(isA<DamageCheckUnavailable>()),
      );
    });
  });

  group('a check that skipped a photo', () {
    test('is refused when the photos it did read were clean', () async {
      // One side of the packaging was never looked at, so "clean" would be a
      // claim about a side nobody inspected.
      useDetector(DamageCheckResult(
        available: true,
        message: 'No packaging damage detected.',
        report: _report([
          _photo(0, succeeded: true),
          _photo(1, succeeded: false),
        ]),
      ));
      await expectLater(
        damageScan(),
        throwsA(isA<DamageCheckUnavailable>()
            .having((e) => e.message, 'message', contains('1 of 2'))),
      );
    });

    test('still reports damage it found on the photos it read', () async {
      // A defect is a defect whatever happened to the other photos.
      useDetector(DamageCheckResult(
        available: true,
        message: 'Possible packaging damage detected: Dent.',
        isDamaged: true,
        detections: const ['Dent'],
        maxConfidence: 0.9,
        report: _report([
          _photo(0, succeeded: true),
          _photo(1, succeeded: false),
        ]),
      ));
      final record = await damageScan();
      expect(record.status, ComplianceStatus.nonCompliant);
      expect(record.statusBadge,
          'NON-COMPLIANT BASED ON FDA PACKAGING REQUIREMENTS');
    });
  });

  group('a check that ran on every photo', () {
    final clean = DamageCheckResult(
      available: true,
      message: 'No packaging damage detected.',
      report: _report([
        _photo(0, succeeded: true),
        _photo(1, succeeded: true),
      ]),
    );

    test('makes a clean damage scan compliant on packaging', () async {
      useDetector(clean);
      final record = await damageScan();
      expect(record.status, ComplianceStatus.compliant);
      expect(record.statusBadge, 'COMPLIANT WITH FDA PACKAGING REQUIREMENTS');
    });

    test('makes a clean inspection compliant on both', () async {
      useDetector(clean);
      final record = await inspection();
      expect(record.status, ComplianceStatus.compliant);
      expect(record.statusBadge,
          'COMPLIANT WITH FDA LABELING AND PACKAGING REQUIREMENTS');
    });
  });
}
