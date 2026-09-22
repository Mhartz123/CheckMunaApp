import 'package:flutter_test/flutter_test.dart';
import 'package:ui_prototype/models/scan_record.dart';
import 'package:ui_prototype/services/compliance_engine.dart';
import 'package:ui_prototype/services/date_code_parser.dart';
import 'package:ui_prototype/services/fda_dataset_checker.dart';

/// Foil is not required to carry an ingredient list — a sachet or blister
/// strip is usually cut from a larger pack whose carton holds the full label.
/// These pin that a missing list does not fail foil, in either flow that reads
/// a label, while box and bottle are still held to it.

/// A foil label with a readable, in-date expiry and no ingredient list: the
/// only thing that could fail it is the ingredient rule under test.
const Map<PhotoSlot, String> _foilLabel = <PhotoSlot, String>{
  PhotoSlot.front: 'Kremil-S',
  PhotoSlot.expiration: 'EXP 10/2028',
  PhotoSlot.ingredients: '',
};

final DateCode _inDate = DateCode(
  expiry: DateTime(2028, 10, 31),
  status: DateCodeStatus.parsed,
);

Future<ScanRecord> _label(
  PackagingType? type, {
  bool declaredMissing = false,
}) =>
    ComplianceEngine.analyzeLabel(
      textBySlot: _foilLabel,
      combinedText: _foilLabel.values.join('\n'),
      // Null keeps the semantic tier from firing, so no ONNX model is loaded.
      ocrConfidence: null,
      dateCode: _inDate,
      ingredientsDeclaredMissing: declaredMissing,
      packagingType: type,
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FdaDatasetChecker.ensureLoaded();
  });

  test('only foil is exempt from the ingredient-list requirement', () {
    expect(PackagingType.foil.requiresIngredientList, isFalse);
    expect(PackagingType.box.requiresIngredientList, isTrue);
    expect(PackagingType.bottle.requiresIngredientList, isTrue);
  });

  group('label check', () {
    test('foil with no ingredient list is compliant', () async {
      final record = await _label(PackagingType.foil);
      expect(record.status, ComplianceStatus.compliant);
      expect(record.reasons.any((r) => r.toLowerCase().contains('ingredient')),
          isFalse);
    });

    test('foil declared as having no ingredient list is compliant', () async {
      final record = await _label(PackagingType.foil, declaredMissing: true);
      expect(record.status, ComplianceStatus.compliant);
    });

    test('box and bottle with no ingredient list are still non-compliant',
        () async {
      for (final type in [PackagingType.box, PackagingType.bottle]) {
        final record = await _label(type);
        expect(record.status, ComplianceStatus.nonCompliant, reason: type.name);
        expect(
          record.reasons.any((r) => r.toLowerCase().contains('ingredient')),
          isTrue,
          reason: '${type.name} must say why it failed',
        );
      }
    });

    test('a label check with no packaging type keeps the old requirement',
        () async {
      // Records and callers from before the picker was added to Check Labels.
      final record = await _label(null);
      expect(record.status, ComplianceStatus.nonCompliant);
    });

    test('the label record now remembers its packaging type', () async {
      final record = await _label(PackagingType.foil);
      expect(record.packagingType, PackagingType.foil);
    });

    test('foil is still failed by an expired date', () async {
      // The exemption is for the ingredient list only, not the whole label.
      final record = await ComplianceEngine.analyzeLabel(
        textBySlot: _foilLabel,
        combinedText: _foilLabel.values.join('\n'),
        ocrConfidence: null,
        dateCode: DateCode(
          expiry: DateTime(2020, 1, 31),
          status: DateCodeStatus.parsed,
        ),
        packagingType: PackagingType.foil,
      );
      expect(record.status, ComplianceStatus.nonCompliant);
    });
  });

  group('inspection mode', () {
    Future<ScanRecord> inspect(PackagingType type) =>
        ComplianceEngine.analyzeInspection(
          textBySlot: _foilLabel,
          combinedText: _foilLabel.values.join('\n'),
          packagingType: type,
          // No photos: the damage check reports itself unavailable, which
          // does not fail a scan, so the label side alone decides here.
          boxPhotoPaths: const <String>[],
          ocrConfidence: null,
          dateCode: _inDate,
        );

    test('foil with no ingredient list is compliant', () async {
      final record = await inspect(PackagingType.foil);
      expect(record.status, ComplianceStatus.compliant);
    });

    test('box with no ingredient list is still non-compliant', () async {
      final record = await inspect(PackagingType.box);
      expect(record.status, ComplianceStatus.nonCompliant);
    });
  });
}
