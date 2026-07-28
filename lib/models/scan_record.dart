import 'package:flutter/material.dart';

/// Which of the two independent inspections a record came from. The app's two
/// home-screen buttons each start one of these; a record is never both.
enum ScanType {
  /// Label compliance: 3 close-ups → OCR → FDA advisory / expiry / ingredient
  /// checks. Reports product name, expiration date, and whether all required
  /// labels are present.
  label,

  /// Physical packaging damage: 4 full-frame box shots → YOLO11n detector.
  /// Reports whether damage was found and where.
  damage,
}

extension ScanTypeX on ScanType {
  /// Persisted discriminator in data.json.
  String get id => this == ScanType.label ? 'LABEL' : 'DAMAGE';

  String get shortLabel => this == ScanType.label ? 'LABEL' : 'DAMAGE';

  String get title =>
      this == ScanType.label ? 'Label Check' : 'Physical Damage Check';

  static ScanType fromId(String? s) =>
      s == 'DAMAGE' ? ScanType.damage : ScanType.label;
}

/// Compliance classification for a saved record.
enum ComplianceStatus { compliant, nonCompliant, banned }

/// The three fixed label-capture slots for a single product scan. Each slot's
/// OCR text is routed straight to its own record field (see LabelParser)
/// instead of being guessed out of one combined blob of text. These are the
/// close-up label shots — cropped to the framing guide before OCR. The
/// ingredient-list slot feeds the "ingredient list present?" compliance check.
enum PhotoSlot { front, expiration, ingredients }

extension PhotoSlotX on PhotoSlot {
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

/// The four box-capture slots for the packaging-damage check. These are
/// full-frame shots of the whole box (no crop, no OCR) fed to the YOLO11n
/// damage detector — a separate inspection from the label slots above.
enum BoxSlot { front, side1, side2, back }

extension BoxSlotX on BoxSlot {
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

  /// Human-readable side name used in damage reports ("Front", "Side 1", …).
  String get sideName {
    switch (this) {
      case BoxSlot.front:
        return 'Front';
      case BoxSlot.side1:
        return 'Side 1';
      case BoxSlot.side2:
        return 'Side 2';
      case BoxSlot.back:
        return 'Back';
    }
  }

  static BoxSlot? fromFileBaseName(String? s) {
    for (final slot in BoxSlot.values) {
      if (slot.fileBaseName == s) return slot;
    }
    return null;
  }
}

/// Damage found on one side of the box. The shipped detector is single-class
/// (`names = {0: 'Damage-detection-on-medicine-v2'}`), so it can tell you
/// *that* a side is damaged, how many separate spots, and how confident it is —
/// but not what kind of damage. Reports say "Damage" until the model is
/// retrained with per-type classes; [label] is what carries that type through
/// when it is.
class DamageFinding {
  final BoxSlot slot;

  /// Detector class name for this finding. Single-class today, so always
  /// 'Damage' — kept as a string so a multi-class retrain needs no app change.
  final String label;

  /// How many separate damage spots survived NMS on this side.
  final int spotCount;

  /// Highest detection confidence (0..1) on this side.
  final double confidence;

  const DamageFinding({
    required this.slot,
    required this.label,
    required this.spotCount,
    required this.confidence,
  });

  /// "Front — Damage, 2 spots (78% confidence)"
  String get summary {
    final spots = spotCount == 1 ? '1 spot' : '$spotCount spots';
    return '${slot.sideName} — $label, $spots '
        '(${(confidence * 100).toStringAsFixed(0)}% confidence)';
  }

  Map<String, dynamic> toJson() => {
        'slot': slot.fileBaseName,
        'label': label,
        'spotCount': spotCount,
        'confidence': confidence,
      };

  static DamageFinding? fromJson(Map<String, dynamic> json) {
    final slot = BoxSlotX.fromFileBaseName(json['slot'] as String?);
    if (slot == null) return null;
    return DamageFinding(
      slot: slot,
      label: json['label'] as String? ?? 'Damage',
      spotCount: (json['spotCount'] as num?)?.toInt() ?? 1,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Result of a packaging-damage check via [DamageDetectionService].
/// [available] is false when the check couldn't run at all (model failed to
/// load, every image failed to decode) — distinct from [isDamaged], which is
/// only meaningful when [available] is true.
class DamageCheckResult {
  final bool available;
  final String message;
  final bool isDamaged;

  /// Per-side breakdown — which box faces the damage was found on. Empty when
  /// nothing was detected or the check didn't run.
  final List<DamageFinding> findings;

  /// Highest detection confidence (0..1) across all box photos.
  final double maxConfidence;

  const DamageCheckResult({
    required this.available,
    required this.message,
    this.isDamaged = false,
    this.findings = const [],
    this.maxConfidence = 0.0,
  });

  const DamageCheckResult.placeholder()
      : available = false,
        message = 'Damage detection not yet available',
        isDamaged = false,
        findings = const [],
        maxConfidence = 0.0;

  /// Distinct damage type names detected, for a compact "what damage it is"
  /// line. Single-class today, so this is normally just ['Damage'].
  List<String> get damageTypes =>
      findings.map((f) => f.label).toSet().toList();

  /// Total damage spots across every side.
  int get totalSpots =>
      findings.fold<int>(0, (sum, f) => sum + f.spotCount);

  /// Box sides damage was found on, e.g. "Front, Back".
  String get affectedSides =>
      findings.map((f) => f.slot.sideName).join(', ');

  Map<String, dynamic> toJson() => {
        'available': available,
        'message': message,
        'isDamaged': isDamaged,
        'findings': [for (final f in findings) f.toJson()],
        'maxConfidence': maxConfidence,
      };

  factory DamageCheckResult.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DamageCheckResult.placeholder();
    final rawFindings = (json['findings'] as List?) ?? const [];
    final findings = <DamageFinding>[];
    for (final raw in rawFindings) {
      if (raw is! Map) continue;
      final f = DamageFinding.fromJson(raw.cast<String, dynamic>());
      if (f != null) findings.add(f);
    }
    return DamageCheckResult(
      available: json['available'] as bool? ?? false,
      message:
          json['message'] as String? ?? 'Damage detection not yet available',
      isDamaged: json['isDamaged'] as bool? ?? false,
      findings: findings,
      maxConfidence: (json['maxConfidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Structured result of a scan — produced by ComplianceEngine and persisted as
/// each record's data.json.
///
/// A record belongs to exactly one [type]. Label records carry the OCR/FDA
/// fields and leave [damageCheck] at its placeholder; damage records carry
/// [damageCheck] and leave the label fields blank. The UI reads [type] first
/// and only shows the half that applies.
class ScanRecord {
  final ScanType type;
  final ComplianceStatus status;
  final String matchedKeyword;
  final List<String> reasons;
  final String productName;
  final String expiration;
  final String ingredients;

  /// Whether every required label element (product name, expiration date,
  /// ingredient list) was found on the packaging. Label records only.
  final bool allLabelsPresent;

  final String extractedText;
  final DamageCheckResult damageCheck;
  final DateTime scannedAt;

  const ScanRecord({
    required this.type,
    required this.status,
    required this.matchedKeyword,
    required this.reasons,
    required this.productName,
    required this.expiration,
    required this.ingredients,
    required this.allLabelsPresent,
    required this.extractedText,
    required this.damageCheck,
    required this.scannedAt,
  });

  bool get isLabelCheck => type == ScanType.label;
  bool get isDamageCheck => type == ScanType.damage;

  String get statusLabel {
    switch (status) {
      case ComplianceStatus.compliant:
        return 'COMPLIANT';
      case ComplianceStatus.nonCompliant:
        return 'NON-COMPLIANT';
      case ComplianceStatus.banned:
        return 'WARNING / BANNED';
    }
  }

  Map<String, dynamic> toJson() => {
        'scanType': type.id,
        'status': statusLabel,
        'matchedKeyword': matchedKeyword,
        'reasons': reasons,
        'productName': productName,
        'expiration': expiration,
        'ingredients': ingredients,
        'allLabelsPresent': allLabelsPresent,
        'extractedText': extractedText,
        'damageCheck': damageCheck.toJson(),
        'scannedAt': scannedAt.toIso8601String(),
      };

  factory ScanRecord.fromJson(Map<String, dynamic> json) => ScanRecord(
        type: ScanTypeX.fromId(json['scanType'] as String?),
        status: _statusFromLabel(json['status'] as String? ?? ''),
        matchedKeyword: json['matchedKeyword'] as String? ?? '—',
        reasons: (json['reasons'] as List?)?.cast<String>() ?? const [],
        productName: json['productName'] as String? ?? '—',
        expiration: json['expiration'] as String? ?? '—',
        ingredients: json['ingredients'] as String? ?? '—',
        allLabelsPresent: json['allLabelsPresent'] as bool? ?? false,
        extractedText: json['extractedText'] as String? ?? '',
        damageCheck: DamageCheckResult.fromJson(
            json['damageCheck'] as Map<String, dynamic>?),
        scannedAt: DateTime.tryParse(json['scannedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  static ComplianceStatus _statusFromLabel(String s) {
    if (s == 'COMPLIANT') return ComplianceStatus.compliant;
    if (s == 'WARNING / BANNED') return ComplianceStatus.banned;
    return ComplianceStatus.nonCompliant;
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
      case ComplianceStatus.banned:
        return const Color(0xFFF44336);
    }
  }

  IconData get statusIcon {
    switch (status) {
      case ComplianceStatus.compliant:
        return Icons.check_circle;
      case ComplianceStatus.nonCompliant:
        return Icons.warning;
      case ComplianceStatus.banned:
        return Icons.dangerous;
    }
  }

  String get statusTitle {
    switch (status) {
      case ComplianceStatus.compliant:
        return 'Compliant';
      case ComplianceStatus.nonCompliant:
        return 'Non-Compliant';
      case ComplianceStatus.banned:
        return 'Banned';
    }
  }

  /// Headline for a damage record's card/detail — damage records don't use the
  /// FDA compliance wording.
  String get damageTitle => damageCheck.available
      ? (damageCheck.isDamaged ? 'Damage detected' : 'No damage detected')
      : 'Check unavailable';

  Color get damageColor => damageCheck.available
      ? (damageCheck.isDamaged
          ? const Color(0xFFC62828)
          : const Color(0xFF2E7D32))
      : const Color(0xFF6A8F6E);

  IconData get damageIcon => damageCheck.available
      ? (damageCheck.isDamaged
          ? Icons.warning_amber_rounded
          : Icons.check_circle_outline)
      : Icons.help_outline;

  String get note {
    switch (status) {
      case ComplianceStatus.compliant:
        return 'Product is compliant with the FDA and is safe to consume. Please refer to instructions / professionals with regards to safe dosage.';
      case ComplianceStatus.nonCompliant:
        return 'Product is non-compliant with the FDA and is inadvisable to consume. Please refer to the local FDA hotline near you to report this occurrence.';
      case ComplianceStatus.banned:
        return 'Product is banned by the FDA, dangerous to consume. Please immediately refer to the local FDA hotline near you to report this occurrence.';
    }
  }

  Color get noteColor {
    switch (status) {
      case ComplianceStatus.compliant:
        return Colors.black54;
      case ComplianceStatus.nonCompliant:
      case ComplianceStatus.banned:
        return const Color(0xFFE57373);
    }
  }
}
