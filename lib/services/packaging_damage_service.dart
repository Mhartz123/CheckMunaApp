import '../models/scan_record.dart';
import 'damage_detection_service.dart';

/// ── HOW TO PLUG IN A NEW MODEL ──────────────────────────────────────────
///
/// Damage detection is split one [PackagingDamageDetector] per
/// [PackagingType], registered in [PackagingDamageService].
/// Every type has a real model ([BoxDamageDetector] / [FoilDamageDetector] /
/// [BottleDamageDetector], backed by the on-device YOLO ONNX models in
/// `damage_detection_service.dart`). Swapping in a different model is a
/// two-step change and nothing else in the app needs to know:
///
///   1. Write a new class implementing [PackagingDamageDetector] (model load,
///      preprocessing, inference, and NMS/threshold logic all live inside
///      it — for another Ultralytics YOLO export, add a
///      [DamageDetectionService] preset and wrap it like
///      [BoxDamageDetector]).
///   2. Register it in [PackagingDamageService._detectors] below, e.g.:
///         PackagingType.foil: FoilYoloDetector(),
///
/// ComplianceEngine, CameraScreen, and every UI screen only ever go through
/// [PackagingDamageService.check] / [PackagingDamageService.warmUp] — they
/// never reference a concrete detector, so none of them change.

/// Runs a damage check against a set of full-frame packaging photos for one
/// [PackagingType]. Implementations should never throw — report failures via
/// [DamageCheckResult.available] = false instead, so a scan always completes.
abstract class PackagingDamageDetector {
  Future<DamageCheckResult> check(List<String> photoPaths);

  /// Optional: kick off model loading early (see
  /// [PackagingDamageService.warmUp]). Default is a no-op for detectors with
  /// nothing to preload.
  Future<void> warmUp() async {}
}

/// The on-device YOLO11n detector for cardboard boxes. Thin wrapper around
/// [DamageDetectionService.box], which owns preprocessing/inference/NMS.
class BoxDamageDetector implements PackagingDamageDetector {
  @override
  Future<DamageCheckResult> check(List<String> photoPaths) =>
      DamageDetectionService.box.check(photoPaths);

  @override
  Future<void> warmUp() => DamageDetectionService.box.warmUp();
}

/// The on-device YOLOv5nu detector for foil packaging (sachets, blister
/// packs). Thin wrapper around [DamageDetectionService.foil].
class FoilDamageDetector implements PackagingDamageDetector {
  @override
  Future<DamageCheckResult> check(List<String> photoPaths) =>
      DamageDetectionService.foil.check(photoPaths);

  @override
  Future<void> warmUp() => DamageDetectionService.foil.warmUp();
}

/// The on-device YOLOv8n detector for bottles. Thin wrapper around
/// [DamageDetectionService.bottle].
class BottleDamageDetector implements PackagingDamageDetector {
  @override
  Future<DamageCheckResult> check(List<String> photoPaths) =>
      DamageDetectionService.bottle.check(photoPaths);

  @override
  Future<void> warmUp() => DamageDetectionService.bottle.warmUp();
}

/// Facade the rest of the app calls through — routes each check to the
/// detector registered for that [PackagingType]. See the module doc above
/// for how to swap in a different model.
class PackagingDamageService {
  static final Map<PackagingType, PackagingDamageDetector> _detectors = {
    PackagingType.box: BoxDamageDetector(),
    PackagingType.foil: FoilDamageDetector(),
    PackagingType.bottle: BottleDamageDetector(),
  };

  /// Swaps in a different detector for a packaging type — this is the one
  /// line a future model integration needs to change, if you'd rather patch
  /// it here than edit the map literal above directly.
  static void register(PackagingType type, PackagingDamageDetector detector) {
    _detectors[type] = detector;
  }

  static Future<DamageCheckResult> check(
      PackagingType type,
      List<String> photoPaths,
      ) {
    final detector = _detectors[type];
    if (detector == null) {
      return Future.value(const DamageCheckResult(
        available: false,
        message: 'No damage detector registered for this packaging type.',
      ));
    }
    return detector.check(photoPaths);
  }

  /// Warms up just the detector for [type] — called from CameraScreen once
  /// the user has picked a packaging type, so only the relevant model (if
  /// any) pays load latency.
  static Future<void> warmUp(PackagingType type) async {
    try {
      await _detectors[type]?.warmUp();
    } catch (_) {
      // Warm-up failures surface again (and get reported properly) the next
      // time check() actually runs.
    }
  }
}