import 'package:flutter/material.dart';

import 'damage_report.dart';
import 'scan_timings.dart';

/// Compliance classification for a saved record.
/// The three verdicts a scan can produce.
///
/// [warning] is what an FDA advisory-index hit routes to — deliberately NOT
/// [nonCompliant]. An advisory match says the product name resembles one on
/// the FDA's warned/unregistered list, which is a flag for manual
/// verification, not a finding the app can make on its own.
enum ComplianceStatus { compliant, nonCompliant, warning }

/// Which check(s) a [ScanRecord] represents. Label checking and box/damage
/// checking are two independent scan flows (see CameraScreen/
/// ComplianceEngine), each producing its own record — [label] or [damage].
/// [both] exists only to keep loading old records (saved before this split)
/// working: they carry both label and damage data in one record.
enum ScanKind { label, damage, both }

/// Which kind of packaging a damage check ([ScanKind.damage] or
/// [ScanKind.both]) was run against. The user picks one on
/// PackagingTypeScreen before the camera opens for any flow that includes a
/// damage step.
///
/// Every type has an on-device detection model ([hasModel]). A replacement
/// model only needs a new `PackagingDamageDetector` registered in
/// `packaging_damage_service.dart`; nothing else in the app needs to change.
enum PackagingType { box, foil, bottle }

extension PackagingTypeX on PackagingType {
  String get label {
    switch (this) {
      case PackagingType.box:
        return 'Box';
      case PackagingType.foil:
        return 'Foil';
      case PackagingType.bottle:
        return 'Bottle';
    }
  }

  /// The packaging photos taken for this type, in capture order.
  ///
  /// Foil takes only the front and back: a sachet or blister sheet is flat,
  /// so its edges are a few millimetres of seam, not panels that can carry
  /// damage of their own, and photographing them just feeds the detector two
  /// frames of mostly background.
  List<BoxSlot> get captureSlots {
    switch (this) {
      case PackagingType.foil:
        return const [BoxSlot.front, BoxSlot.back];
      case PackagingType.box:
      case PackagingType.bottle:
        return BoxSlot.values;
    }
  }

  /// Whether a missing ingredient list makes a product of this packaging
  /// non-compliant.
  ///
  /// Not for foil: a sachet or blister strip is usually a unit dose cut from a
  /// larger pack, and the full label — ingredient list included — lives on
  /// the outer carton rather than on the foil itself. Failing a foil for the
  /// absence of a list it was never expected to carry would flag compliant
  /// product. Foil is still read for an ingredient list when one is printed;
  /// its absence just stops counting against the verdict.
  bool get requiresIngredientList => this != PackagingType.foil;

  /// Whether a real detection model is wired up for this packaging type yet.
  /// All three ship a model today; kept so the picker can grey a type out
  /// again if one is ever pulled.
  bool get hasModel => true;

  IconData get icon {
    switch (this) {
      case PackagingType.box:
        return Icons.inventory_2_outlined;
      case PackagingType.foil:
        return Icons.texture_outlined;
      case PackagingType.bottle:
        return Icons.liquor_outlined;
    }
  }
}

/// The three fixed label-capture slots for a single product scan. Each slot's
/// OCR text is routed straight to its own record field (see LabelParser)
/// instead of being guessed out of one combined blob of text. These are the
/// close-up label shots — cropped to the framing guide before OCR. The
/// ingredient-list slot feeds the "ingredient list present?" compliance check.
enum PhotoSlot { front, expiration, ingredients }

extension PhotoSlotX on PhotoSlot {
  /// How this slot is named in the on-screen timing breakdown.
  String get timingLabel {
    switch (this) {
      case PhotoSlot.front:
        return 'Product name';
      case PhotoSlot.expiration:
        return 'Expiration date';
      case PhotoSlot.ingredients:
        return 'Ingredient list';
    }
  }

  String get fileBaseName {
    switch (this) {
      case PhotoSlot.front:
        return 'front';
      case PhotoSlot.expiration:
        return 'expiration';
      case PhotoSlot.ingredients:
        return 'ingredients';
    }
  }
}

/// Which shape of carton a [PackagingType.box] scan is photographing, asked
/// for right after Box is chosen (see PackagingTypeScreen).
///
/// The capture flow is the same four shots either way — what changes is what
/// the user is told to frame on the two side shots, since "the side" means a
/// square panel on one shape and a narrow strip on another. Keeping it as an
/// enum rather than a free-text note also leaves a place for a shape-specific
/// damage model to hook in later without another round of UI.
enum BoxForm { cube, rectangular, squareSided, upright }

extension BoxFormX on BoxForm {
  String get label {
    switch (this) {
      case BoxForm.cube:
        return 'Cube';
      case BoxForm.rectangular:
        return 'Rectangular';
      case BoxForm.squareSided:
        return 'Rectangular, square sides';
      case BoxForm.upright:
        return 'Upright, square base';
    }
  }

  /// What the user should look at to tell the three apart — phrased around
  /// the carton in their hand, not around the geometry.
  String get description {
    switch (this) {
      case BoxForm.cube:
        return 'Every face is a square — the box is as deep as it is wide '
            'and tall.';
      case BoxForm.rectangular:
        return 'Front and back are rectangles, and the sides are narrow '
            'rectangles too.';
      case BoxForm.squareSided:
        return 'Front and back are rectangles, but each side is a square.';
      case BoxForm.upright:
        return 'Every side is the same upright rectangle — square from '
            'above, and taller than it is wide.';
    }
  }

  /// Width/height of the front panel and of a side panel, used to draw the
  /// little shape diagram next to each option.
  double get frontAspect {
    switch (this) {
      case BoxForm.cube:
        return 1;
      case BoxForm.rectangular:
      case BoxForm.squareSided:
        return 1.6;
      case BoxForm.upright:
        return 0.46;
    }
  }

  double get sideAspect {
    switch (this) {
      case BoxForm.cube:
      case BoxForm.squareSided:
        return 1;
      case BoxForm.rectangular:
        return 0.32;
    // Square from above, so a side is the same panel as the front.
      case BoxForm.upright:
        return 0.46;
    }
  }

  /// How the two side shots are described during capture.
  String get sidePanelNoun {
    switch (this) {
      case BoxForm.cube:
      case BoxForm.squareSided:
        return 'square side';
      case BoxForm.rectangular:
        return 'narrow side';
      case BoxForm.upright:
        return 'upright side';
    }
  }
}

/// The four packaging-capture slots for the damage step. These are
/// full-frame shots of the whole item (no crop, no OCR) sent to whichever
/// [PackagingDamageDetector] handles the chosen [PackagingType] — a separate
/// concern from the label slots above. Shared by every packaging type, but not
/// every type uses all four — see [PackagingTypeX.captureSlots] (foil takes
/// front and back only).
enum BoxSlot { front, side1, side2, back }

extension BoxSlotX on BoxSlot {
  /// How this slot is named on screen and in the per-photo damage report.
  String get label {
    switch (this) {
      case BoxSlot.front:
        return 'Front';
      case BoxSlot.side1:
        return 'Side';
      case BoxSlot.side2:
        return 'Other side';
      case BoxSlot.back:
        return 'Back';
    }
  }

  String get fileBaseName {
    switch (this) {
      case BoxSlot.front:
        return 'box_front';
      case BoxSlot.side1:
        return 'box_side1';
      case BoxSlot.side2:
        return 'box_side2';
      case BoxSlot.back:
        return 'box_back';
    }
  }
}

/// One damage box the detector found, with where it sits on the photo.
///
/// [left]/[top]/[width]/[height] are **normalised to 0..1** against the source
/// photo *after* EXIF orientation is baked in — the same space Flutter's
/// `Image.file` and the PDF renderer draw in. Storing fractions rather than
/// pixels means an overlay lines up at any display size, and a record stays
/// readable if the photo is later resized.
///
/// [sourceIndex] is the position of the photo this box came from within the
/// packaging photos for the scan, in [BoxSlot] order with skipped slots
/// omitted — i.e. the same ordering as `ScanStore.boxPhotosInOrder`, so a
/// saved record can find its way back to the right image.
class DamageDetection {
  final String label;
  final double confidence;
  final double left;
  final double top;
  final double width;
  final double height;
  final int sourceIndex;

  const DamageDetection({
    required this.label,
    required this.confidence,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.sourceIndex,
  });

  double get right => left + width;
  double get bottom => top + height;

  /// Confidence as a whole percentage, for display ("Dent 87%").
  String get confidenceLabel => '${(confidence * 100).round()}%';

  Map<String, dynamic> toJson() => {
    'label': label,
    'confidence': confidence,
    'left': left,
    'top': top,
    'width': width,
    'height': height,
    'sourceIndex': sourceIndex,
  };

  factory DamageDetection.fromJson(Map<String, dynamic> json) =>
      DamageDetection(
        label: json['label'] as String? ?? 'Damage',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        left: (json['left'] as num?)?.toDouble() ?? 0.0,
        top: (json['top'] as num?)?.toDouble() ?? 0.0,
        width: (json['width'] as num?)?.toDouble() ?? 0.0,
        height: (json['height'] as num?)?.toDouble() ?? 0.0,
        sourceIndex: (json['sourceIndex'] as num?)?.toInt() ?? 0,
      );
}

/// Result of a packaging-damage check via a `PackagingDamageDetector` (see
/// `packaging_damage_service.dart`). [available] is false when the check
/// couldn't run at all — e.g. the model failed to load, or inference failed on
/// every photo — distinct from [isDamaged], which is only meaningful when
/// [available] is true.
class DamageCheckResult {
  final bool available;
  final String message;
  final bool isDamaged;
  final List<String> detections;

  /// Where each detection sits on its source photo, for drawing an overlay.
  ///
  /// Parallel to [detections] in content but richer: [detections] stays the
  /// plain class-name list the dashboard payload and older records use, while
  /// [boxes] adds geometry and per-detection confidence. Empty for records
  /// saved before boxes were captured, and for detectors that report classes
  /// without geometry — so always treat an empty [boxes] on a damaged record
  /// as "no overlay available", never as "no damage".
  final List<DamageDetection> boxes;

  /// Highest detection confidence (0..1) the damage model returned across all
  /// packaging photos, used to gate whether "severe" damage counts against
  /// compliance. 0 when nothing was detected or confidence wasn't reported.
  final double maxConfidence;

  /// How long the model actually took on this device — load, preprocessing and
  /// inference (see DamageDetectionService). [ScanTimings.empty] when the
  /// check never ran, or for records saved before timings were measured.
  final ScanTimings timings;

  /// Per-photo timings and confidences for this check, kept unaggregated —
  /// see [DamageSessionReport]. Null when the check never ran, and for records
  /// saved before the report existed.
  final DamageSessionReport? report;

  const DamageCheckResult({
    required this.available,
    required this.message,
    this.isDamaged = false,
    this.detections = const [],
    this.boxes = const [],
    this.maxConfidence = 0.0,
    this.timings = ScanTimings.empty,
    this.report,
  });

  const DamageCheckResult.placeholder()
      : available = false,
        message = 'Damage detection not yet available',
        isDamaged = false,
        detections = const [],
        boxes = const [],
        maxConfidence = 0.0,
        timings = ScanTimings.empty,
        report = null;

  /// Used for label-only scans, where the damage check was never run because
  /// the user chose "Check Labels" rather than a damage-inclusive flow.
  const DamageCheckResult.notPerformed()
      : available = false,
        message = 'Damage check not performed for this scan.',
        isDamaged = false,
        detections = const [],
        boxes = const [],
        maxConfidence = 0.0,
        timings = ScanTimings.empty,
        report = null;

  /// One line naming what was found and how sure the model was, e.g.
  /// "Dent x2 (up to 87%), Scratches (72%)". Falls back to the bare class
  /// list for records saved before per-detection confidence was stored.
  String get detectionSummary {
    if (boxes.isEmpty) return detections.toSet().join(', ');
    final byLabel = <String, List<DamageDetection>>{};
    for (final d in boxes) {
      byLabel.putIfAbsent(d.label, () => []).add(d);
    }
    return byLabel.entries.map((e) {
      final best = e.value
          .map((d) => d.confidence)
          .reduce((a, b) => a > b ? a : b);
      final pct = '${(best * 100).round()}%';
      return e.value.length > 1
          ? '${e.key} ×${e.value.length} (up to $pct)'
          : '${e.key} ($pct)';
    }).join(', ');
  }

  Map<String, dynamic> toJson() => {
    'available': available,
    'message': message,
    'isDamaged': isDamaged,
    'detections': detections,
    'boxes': boxes.map((b) => b.toJson()).toList(),
    'maxConfidence': maxConfidence,
    if (timings.isNotEmpty) 'timings': timings.toJson(),
    if (report != null) 'report': report!.toJson(),
  };

  factory DamageCheckResult.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DamageCheckResult.placeholder();
    return DamageCheckResult(
      available: json['available'] as bool? ?? false,
      message: json['message'] as String? ??
          'Damage detection not yet available',
      isDamaged: json['isDamaged'] as bool? ?? false,
      detections: (json['detections'] as List?)?.cast<String>() ?? const [],
      boxes: (json['boxes'] as List?)
          ?.map((b) => DamageDetection.fromJson(b as Map<String, dynamic>))
          .toList() ??
          const [],
      maxConfidence: (json['maxConfidence'] as num?)?.toDouble() ?? 0.0,
      timings: ScanTimings.fromJson(json['timings'] as List?),
      report: DamageSessionReport.fromJson(
          (json['report'] as Map?)?.cast<String, dynamic>()),
    );
  }
}

/// Structured result of a scan — produced by ComplianceEngine and persisted
/// as each record's data.json.
class ScanRecord {
  final ScanKind kind;
  final ComplianceStatus status;
  final String matchedKeyword;
  final List<String> reasons;
  final String productName;
  final String expiration;
  final String ingredients;
  final String extractedText;
  final DamageCheckResult damageCheck;

  /// Which packaging type the damage check ran against — null for a
  /// label-only ([ScanKind.label]) record, or for records saved before this
  /// field existed.
  final PackagingType? packagingType;

  /// Measured on-device cost of the ML work in this scan — OCR per label slot,
  /// and the damage model's load/preprocess/inference. [ScanTimings.empty] for
  /// records saved before timings were measured, which simply show no timing
  /// section.
  final ScanTimings timings;

  final DateTime scannedAt;

  const ScanRecord({
    required this.kind,
    required this.status,
    required this.matchedKeyword,
    required this.reasons,
    required this.productName,
    required this.expiration,
    required this.ingredients,
    required this.extractedText,
    required this.damageCheck,
    this.packagingType,
    this.timings = ScanTimings.empty,
    required this.scannedAt,
  });

  /// Whether this record carries label data (product/expiration/ingredients)
  /// worth displaying — true for [ScanKind.label] and legacy [ScanKind.both]
  /// records, false for a damage-only scan.
  bool get hasLabelData => kind != ScanKind.damage;

  /// Whether this record carries a damage check worth displaying — true for
  /// [ScanKind.damage] and legacy [ScanKind.both] records, false for a
  /// label-only scan.
  bool get hasDamageData => kind != ScanKind.label;

  String get statusLabel {
    switch (status) {
      case ComplianceStatus.compliant:
        return 'COMPLIANT';
      case ComplianceStatus.nonCompliant:
        return 'NON-COMPLIANT';
      case ComplianceStatus.warning:
        return warningLabel;
    }
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'status': statusLabel,
    'matchedKeyword': matchedKeyword,
    'reasons': reasons,
    'productName': productName,
    'expiration': expiration,
    'ingredients': ingredients,
    'extractedText': extractedText,
    'damageCheck': damageCheck.toJson(),
    if (packagingType != null) 'packagingType': packagingType!.name,
    if (timings.isNotEmpty) 'timings': timings.toJson(),
    'scannedAt': scannedAt.toIso8601String(),
  };

  factory ScanRecord.fromJson(Map<String, dynamic> json) => ScanRecord(
    kind: _kindFromName(json['kind'] as String?),
    status: _statusFromLabel(json['status'] as String? ?? ''),
    matchedKeyword: json['matchedKeyword'] as String? ?? '—',
    reasons: (json['reasons'] as List?)?.cast<String>() ?? const [],
    productName: json['productName'] as String? ?? '—',
    expiration: json['expiration'] as String? ?? '—',
    ingredients: json['ingredients'] as String? ?? '—',
    extractedText: json['extractedText'] as String? ?? '',
    damageCheck:
    DamageCheckResult.fromJson(json['damageCheck'] as Map<String, dynamic>?),
    packagingType: _packagingTypeFromName(json['packagingType'] as String?),
    timings: ScanTimings.fromJson(json['timings'] as List?),
    scannedAt: DateTime.tryParse(json['scannedAt'] as String? ?? '') ??
        DateTime.now(),
  );

  /// The serialized status string new records write for
  /// [ComplianceStatus.warning].
  static const String warningLabel = 'WARNING';

  /// What records saved before the Banned→Warning rename carry. Still has to
  /// match when loading, filtering, and reporting, or every historical
  /// advisory hit silently falls through to NON-COMPLIANT.
  static const List<String> legacyWarningLabels = ['WARNING / BANNED', 'BANNED'];

  /// True if [s] is a warning status in either the current or a legacy
  /// spelling. Used by anything comparing raw persisted status strings
  /// (records list filters, the PDF report builder).
  static bool isWarningLabel(String s) =>
      s == warningLabel || legacyWarningLabels.contains(s);

  static ComplianceStatus _statusFromLabel(String s) {
    if (s == 'COMPLIANT') return ComplianceStatus.compliant;
    if (isWarningLabel(s)) return ComplianceStatus.warning;
    return ComplianceStatus.nonCompliant;
  }

  /// Records saved before the label/damage split didn't store a `kind` at
  /// all — those are treated as [ScanKind.both] so they keep displaying both
  /// their label and damage sections exactly as before.
  static ScanKind _kindFromName(String? name) {
    if (name == null) return ScanKind.both;
    return ScanKind.values.firstWhere(
          (k) => k.name == name,
      orElse: () => ScanKind.both,
    );
  }

  static PackagingType? _packagingTypeFromName(String? name) {
    if (name == null) return null;
    for (final t in PackagingType.values) {
      if (t.name == name) return t;
    }
    return null;
  }
}

/// UI-facing presentation helpers for a [ScanRecord]'s status.
extension ScanRecordUi on ScanRecord {
  Color get statusColor {
    switch (status) {
      case ComplianceStatus.compliant:
        return const Color(0xFF4CAF50);
      case ComplianceStatus.nonCompliant:
        return const Color(0xFFFF9800);
      case ComplianceStatus.warning:
        return const Color(0xFFF44336);
    }
  }

  IconData get statusIcon {
    switch (status) {
      case ComplianceStatus.compliant:
        return Icons.check_circle;
      case ComplianceStatus.nonCompliant:
        return Icons.warning;
      case ComplianceStatus.warning:
        return Icons.report_problem;
    }
  }

  String get statusTitle {
    switch (status) {
      case ComplianceStatus.compliant:
        return 'Compliant';
      case ComplianceStatus.nonCompliant:
        return kind == ScanKind.damage ? 'Damaged' : 'Non-Compliant';
      case ComplianceStatus.warning:
        return 'Warned';
    }
  }

  /// What the UI prints for this record's verdict, in the four words the app
  /// is allowed to use: Compliant, Non-Compliant, Warned, Damaged.
  ///
  /// Kept separate from [statusLabel], which is the string written to disk and
  /// matched on load — renaming that would strand every saved record.
  ///
  /// The app never says the FDA verified, approved or cleared anything. It
  /// compares what is printed on the pack against the FDA's published registry
  /// and advisory lists; a pack that matches nothing on those lists has passed
  /// this app's checks, which is not the FDA passing judgement on the pack in
  /// the user's hand. "FDA VERIFIED" claimed exactly that, and a user acting
  /// on it would be acting on an assurance nobody gave.
  String get statusBadge {
    switch (status) {
      case ComplianceStatus.compliant:
        return 'COMPLIANT';
      case ComplianceStatus.nonCompliant:
        return kind == ScanKind.damage ? 'DAMAGED' : 'NON-COMPLIANT';
      case ComplianceStatus.warning:
        return 'WARNED';
    }
  }

  String get note {
    switch (status) {
      case ComplianceStatus.compliant:
        return 'This label passed every check the app runs. That is a check of what is printed on the packaging against FDA registry and advisory data — not an FDA endorsement of this pack. Follow the product instructions and ask a pharmacist or physician about safe dosage.';
      case ComplianceStatus.nonCompliant:
        return 'This label failed one or more of the checks this app runs and the product is inadvisable to consume. Please refer to the local FDA hotline near you to report this occurrence.';
      case ComplianceStatus.warning:
        return 'This product matched an FDA advisory and needs manual checking before sale or use. Please refer to the local FDA hotline near you to confirm its status.';
    }
  }

  Color get noteColor {
    switch (status) {
      case ComplianceStatus.compliant:
        return Colors.black54;
      case ComplianceStatus.nonCompliant:
      case ComplianceStatus.warning:
        return const Color(0xFFE57373);
    }
  }
}