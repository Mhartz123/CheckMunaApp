import 'package:flutter_test/flutter_test.dart';
import 'package:ui_prototype/models/damage_report.dart';
import 'package:ui_prototype/models/scan_record.dart';

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

DamagePhotoReport _photo(
  int index,
  String label, {
  double pre = 40,
  double infer = 100,
  bool ok = true,
  List<DamageDetection> detections = const [],
}) =>
    DamagePhotoReport(
      index: index,
      label: label,
      preprocessMs: pre,
      inferenceMs: infer,
      succeeded: ok,
      detections: detections,
    );

DamageSessionReport _session(List<DamagePhotoReport> photos,
        {double? loadMs, String subject = 'box'}) =>
    DamageSessionReport(
      subject: subject,
      modelAsset: 'assets/box_damage_yolo11n_int8.onnx',
      inputSize: 416,
      confThreshold: 0.35,
      modelLoadMs: loadMs,
      photos: photos,
    );

void main() {
  group('per-photo figures', () {
    test('a photo reports its own timings and confidences', () {
      final p = _photo(0, 'Front', pre: 38.5, infer: 121.5, detections: [
        _det('Structural deformation', 0.82),
        _det('Label aberration', 0.42),
      ]);

      expect(p.totalMs, closeTo(160, 1e-9));
      expect(p.detectionCount, 2);
      expect(p.maxConfidence, closeTo(0.82, 1e-9));
      expect(p.meanConfidence, closeTo(0.62, 1e-9));
      expect(p.isClean, isFalse);
    });

    test('a photo that ran and found nothing is clean', () {
      expect(_photo(0, 'Back').isClean, isTrue);
      expect(_photo(0, 'Back').maxConfidence, 0);
    });

    test('a photo that failed is not clean', () {
      // The distinction the whole report hangs on: a photo that could not be
      // read is not evidence that the packaging was undamaged.
      final failed = _photo(0, 'Side', ok: false);
      expect(failed.isClean, isFalse);
      expect(failed.detectionCount, 0);
    });
  });

  group('session roll-up', () {
    test('totals, means and the spread across four photos', () {
      final r = _session([
        _photo(0, 'Front', pre: 40, infer: 100, detections: [_det('Dent', 0.9)]),
        _photo(1, 'Side', pre: 30, infer: 80),
        _photo(2, 'Other side', pre: 50, infer: 140, detections: [
          _det('Dent', 0.5, source: 2),
          _det('Label aberration', 0.7, source: 2),
        ]),
        _photo(3, 'Back', pre: 40, infer: 120),
      ], loadMs: 300);

      expect(r.photosTotal, 4);
      expect(r.photosSucceeded, 4);
      expect(r.photosWithDetections, 2);
      expect(r.photosClean, 2);
      expect(r.detectionCount, 3);

      expect(r.totalInferenceMs, closeTo(440, 1e-9));
      expect(r.meanInferenceMs, closeTo(110, 1e-9));
      expect(r.minInferenceMs, closeTo(80, 1e-9));
      expect(r.maxInferenceMs, closeTo(140, 1e-9));
      expect(r.totalPreprocessMs, closeTo(160, 1e-9));

      // Session total includes the one-time load when this scan paid it.
      expect(r.sessionTotalMs, closeTo(900, 1e-9));

      expect(r.maxConfidence, closeTo(0.9, 1e-9));
      expect(r.meanConfidence, closeTo(0.7, 1e-9));
    });

    test('a failed photo is excluded from the per-image mean', () {
      // Averaging over four when only three ran would report the model as
      // faster than it was.
      final r = _session([
        _photo(0, 'Front', infer: 90),
        _photo(1, 'Side', infer: 110),
        _photo(2, 'Other side', infer: 100),
        _photo(3, 'Back', ok: false, pre: 0, infer: 0),
      ]);

      expect(r.photosSucceeded, 3);
      expect(r.photosFailed, 1);
      expect(r.meanInferenceMs, closeTo(100, 1e-9));
      expect(r.minInferenceMs, closeTo(90, 1e-9));
    });

    test('a clean session reports zero confidence, not an empty average', () {
      final r = _session([_photo(0, 'Front'), _photo(1, 'Back')]);
      expect(r.detectionCount, 0);
      expect(r.meanConfidence, 0);
      expect(r.maxConfidence, 0);
      expect(r.photosClean, 2);
    });

    test('session total omits the load when the model was already warm', () {
      final r = _session([_photo(0, 'Front', pre: 40, infer: 100)]);
      expect(r.modelLoadMs, isNull);
      expect(r.sessionTotalMs, closeTo(140, 1e-9));
    });
  });

  group('confidence by class', () {
    test('groups detections by class, most frequent first', () {
      final r = _session([
        _photo(0, 'Front', detections: [
          _det('Structural deformation', 0.9),
          _det('Label aberration', 0.4),
        ]),
        _photo(1, 'Back', detections: [
          _det('Structural deformation', 0.5, source: 1),
          _det('Structural deformation', 0.7, source: 1),
        ]),
      ]);

      final stats = r.classStats;
      expect(stats.map((s) => s.label),
          <String>['Structural deformation', 'Label aberration']);

      final deformation = stats.first;
      expect(deformation.count, 3);
      expect(deformation.maxConfidence, closeTo(0.9, 1e-9));
      expect(deformation.minConfidence, closeTo(0.5, 1e-9));
      expect(deformation.meanConfidence, closeTo(0.7, 1e-9));
    });
  });

  group('persistence', () {
    test('a report survives a JSON round-trip inside a damage result', () {
      final original = DamageCheckResult(
        available: true,
        message: 'Possible packaging damage detected: Structural deformation.',
        isDamaged: true,
        detections: const ['Structural deformation'],
        maxConfidence: 0.82,
        report: _session([
          _photo(0, 'Front',
              pre: 38, infer: 121, detections: [_det('Structural deformation', 0.82)]),
          _photo(1, 'Side', ok: false, pre: 0, infer: 0),
        ], loadMs: 275),
      );

      final restored =
          DamageCheckResult.fromJson(original.toJson()).report!;

      expect(restored.subject, 'box');
      expect(restored.inputSize, 416);
      expect(restored.confThreshold, closeTo(0.35, 1e-9));
      expect(restored.modelLoadMs, closeTo(275, 1e-9));
      expect(restored.photos.length, 2);
      expect(restored.photos.first.label, 'Front');
      expect(restored.photos.first.inferenceMs, closeTo(121, 1e-9));
      expect(restored.photos.first.detections.single.confidence,
          closeTo(0.82, 1e-9));
      // The failed photo must not come back as a clean one.
      expect(restored.photos.last.succeeded, isFalse);
      expect(restored.photosFailed, 1);
    });

    test('records saved before reports existed load with none', () {
      final restored = DamageCheckResult.fromJson(<String, dynamic>{
        'available': true,
        'message': 'No packaging damage detected.',
        'isDamaged': false,
      });
      expect(restored.report, isNull);
      expect(restored.available, isTrue);
    });

    test('an empty photo list deserialises to no report at all', () {
      final restored = DamageCheckResult.fromJson(<String, dynamic>{
        'available': true,
        'message': 'x',
        'report': {'subject': 'box', 'photos': <dynamic>[]},
      });
      expect(restored.report, isNull);
    });
  });
}
