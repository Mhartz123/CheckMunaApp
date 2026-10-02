import '../models/scan_record.dart';
import '../models/scan_timings.dart';
import 'date_code_parser.dart';
import 'debug_advisories.dart';
import 'fda_dataset_checker.dart';
import 'label_parser.dart';
import 'packaging_damage_service.dart';

/// Three independent scan flows (see CameraScreen's `CameraMode`), each
/// producing its own [ScanRecord]:
///
///  • [analyzeLabel] — label-only. **Warning:** the product name is checked
///    against the FDA drug-advisory list — [FdaDatasetChecker] (gated
///    distinctive-word match on the front panel). A hit here (and only here)
///    routes to [ComplianceStatus.warning] — deliberately not non-compliant,
///    since an advisory match flags the product for manual verification rather
///    than deciding it. **Otherwise non-compliant if any of:** the
///    printed expiration date has passed (expired); the user verified no
///    expiration date is printed on the packaging; no ingredient list was
///    detected, or the user verified none is printed on the packaging —
///    on a box or bottle only, since that is where the list has to be when it
///    is the product's only primary packaging. Foil is not required to carry
///    one.
///    **Compliant** when none of the above fire.
///
///  • [analyzeDamage] — damage-only. Runs whichever [PackagingDamageDetector]
///    is registered for the given [PackagingType] (see
///    `packaging_damage_service.dart`). **Non-compliant** if it reports
///    damage at or above [damageConfidenceThreshold], **compliant** if it ran
///    on every photo and reports none. If it could not run there is no
///    verdict at all: [DamageCheckUnavailable] is thrown instead of a record.
///
///  • [analyzeInspection] — Inspection Mode: runs both checks above in one
///    scan and combines them into a single verdict (an advisory-matched name
///    overrides everything; otherwise non-compliant if any label check OR the damage
///    check fails; compliant only if everything passes). Throws
///    [DamageCheckUnavailable] on the same terms as [analyzeDamage].
///
/// UI, storage, and report submission consume [ScanRecord] only.
enum ScanStage { matchingRegistry, classifying, checkingDamage }

/// The packaging-damage check could not vouch for the packaging — the model
/// failed to load, or inference failed on photos it needed — so the scan has
/// no verdict to give.
///
/// Thrown rather than returned as a record on purpose. "Nothing was inspected"
/// used to come back as compliant, which is a clean result nobody earned; a
/// scan that could not look at the packaging is a problem to report, not a
/// product to label.
class DamageCheckUnavailable implements Exception {
  /// What went wrong, in words fit to show the user.
  final String message;

  const DamageCheckUnavailable(this.message);

  @override
  String toString() => 'DamageCheckUnavailable: $message';
}

class ComplianceEngine {
  /// The FDA advisory-list check, and with it the only route to
  /// [ComplianceStatus.warning].
  ///
  /// This was off while the bundled list was the uncleaned 20.8k-entry
  /// sheet, whose generic entries false-flagged ordinary products. It now
  /// runs on the cleaned drug-advisory list, with the false-flag gate built
  /// into the asset and [FdaDatasetChecker] — one or two common words in
  /// common can no longer match. See `scripts/convert_fda_dataset.py`.
  ///
  /// It is matched against the front panel only: the ingredient and expiry
  /// panels are generic words by nature, and are what a product name is not.
  static const bool _advisoryDatasetEnabled = true;

  /// Public so the damage report can draw the line a detection has to cross
  /// to fail a scan, rather than restating the number in the UI.
  ///
  /// Minimum damage-detection confidence (0..1) for packaging damage to
  /// count as non-compliant. This is the single gate: every damage class the
  /// shipped models emit is judged on confidence alone.
  ///
  /// Note this sits ABOVE each detector's own `confThreshold` (0.25–0.35, see
  /// `damage_detection_service.dart`): the detector decides what counts as a
  /// detection worth drawing on the photo, and this decides what counts as
  /// bad enough to fail the scan.
  static const double damageConfidenceThreshold = 0.70;

  /// Kicks off the damage model + FDA dataset asset loads early (e.g. from
  /// CameraScreen.initState) so the first scan's analyze call isn't stuck
  /// paying full load latency while the user is still framing photos.
  /// [packagingType] is optional — pass it (from CameraScreen, once the user
  /// has picked one) to also warm that packaging type's damage detector;
  /// omit it for a label-only scan, which has no damage step to warm.
  static void warmUp({PackagingType? packagingType}) {
    if (_advisoryDatasetEnabled) {
      // ignore: unawaited_futures
      FdaDatasetChecker.ensureLoaded();
    }
    if (packagingType != null) {
      // ignore: unawaited_futures
      PackagingDamageService.warmUp(packagingType);
    }
  }

  // ── Label-only ─────────────────────────────────────────────────────────

  /// Runs the label-compliance check only. [textBySlot] maps each captured
  /// label [PhotoSlot] to the OCR text extracted from that slot's
  /// (guide-cropped) photo (see LabelParser); its [PhotoSlot.front] text is
  /// what the advisory list is matched against. [combinedText] concatenates
  /// all label slots' text, kept as the record's extracted text.
  static Future<ScanRecord> analyzeLabel({
    required Map<PhotoSlot, String> textBySlot,
    required String combinedText,
    ScanTimings ocrTimings = ScanTimings.empty,
    DateCode? dateCode,
    bool expirationDeclaredMissing = false,
    bool ingredientsDeclaredMissing = false,
    PackagingType? packagingType,
    void Function(ScanStage stage)? onStageChange,
  }) async {
    final _LabelSignals s = await _computeLabelSignals(
      textBySlot: textBySlot,
      dateCode: dateCode,
      expirationDeclaredMissing: expirationDeclaredMissing,
      ingredientsDeclaredMissing: ingredientsDeclaredMissing,
      ingredientsRequired: packagingType?.requiresIngredientList ?? true,
      onStageChange: onStageChange,
    );

    final ComplianceStatus status = s.advisoryFlagged
        ? ComplianceStatus.warning
        : (s.expired ||
        s.expirationMissing ||
        s.expirationUnreadable ||
        s.ingredientsMissing)
        ? ComplianceStatus.nonCompliant
        : ComplianceStatus.compliant;

    return ScanRecord(
      kind: ScanKind.label,
      status: status,
      matchedKeyword: _matchedLabelKeyword(s),
      reasons: _buildLabelReasons(status: status, s: s),
      productName: s.fields.productName,
      expiration: _expirationLabel(s),
      ingredients: s.fields.ingredients,
      extractedText: combinedText,
      damageCheck: const DamageCheckResult.notPerformed(),
      packagingType: packagingType,
      timings: ocrTimings,
      scannedAt: DateTime.now(),
    );
  }

  // ── Damage-only ────────────────────────────────────────────────────────

  /// Runs the packaging-damage check only, against whichever detector is
  /// registered for [packagingType]. [boxPhotoPaths] are the full-frame
  /// packaging shots fed to that detector.
  static Future<ScanRecord> analyzeDamage({
    required PackagingType packagingType,
    required List<String> boxPhotoPaths,
    List<String>? boxPhotoLabels,
    void Function(ScanStage stage)? onStageChange,
  }) async {
    final damage = await _computeDamage(
        packagingType, boxPhotoPaths, boxPhotoLabels, onStageChange);
    final bool damageFails = _damageFails(damage);
    _requireDamageVerdict(damage, damageFails);

    final ComplianceStatus status = damageFails
        ? ComplianceStatus.nonCompliant
        : ComplianceStatus.compliant;

    return ScanRecord(
      kind: ScanKind.damage,
      status: status,
      matchedKeyword: damageFails ? 'packaging damage' : '—',
      reasons: damageFails ? [_damageReason(damage)] : const [],
      productName: '—',
      expiration: '—',
      ingredients: '—',
      extractedText: '',
      damageCheck: damage,
      packagingType: packagingType,
      timings: damage.timings,
      scannedAt: DateTime.now(),
    );
  }

  // ── Inspection Mode (both) ────────────────────────────────────────────

  /// Runs the label check AND the packaging-damage check in one scan,
  /// combining them into a single verdict. [textBySlot]/[combinedText] are
  /// the label-side inputs (see [analyzeLabel]);
  /// [packagingType]/[boxPhotoPaths] are the damage-side inputs (see
  /// [analyzeDamage]).
  static Future<ScanRecord> analyzeInspection({
    required Map<PhotoSlot, String> textBySlot,
    required String combinedText,
    required PackagingType packagingType,
    required List<String> boxPhotoPaths,
    List<String>? boxPhotoLabels,
    ScanTimings ocrTimings = ScanTimings.empty,
    DateCode? dateCode,
    bool expirationDeclaredMissing = false,
    bool ingredientsDeclaredMissing = false,
    void Function(ScanStage stage)? onStageChange,
  }) async {
    final _LabelSignals s = await _computeLabelSignals(
      textBySlot: textBySlot,
      dateCode: dateCode,
      expirationDeclaredMissing: expirationDeclaredMissing,
      ingredientsDeclaredMissing: ingredientsDeclaredMissing,
      ingredientsRequired: packagingType.requiresIngredientList,
      onStageChange: onStageChange,
    );
    final damage = await _computeDamage(
        packagingType, boxPhotoPaths, boxPhotoLabels, onStageChange);
    final bool damageFails = _damageFails(damage);
    _requireDamageVerdict(damage, damageFails);

    final ComplianceStatus status = s.advisoryFlagged
        ? ComplianceStatus.warning
        : (s.expired ||
        s.expirationMissing ||
        s.expirationUnreadable ||
        s.ingredientsMissing ||
        damageFails)
        ? ComplianceStatus.nonCompliant
        : ComplianceStatus.compliant;

    final reasons = <String>[
      ..._buildLabelReasons(status: status, s: s, omitFallback: true),
      if (damageFails) _damageReason(damage),
    ];
    if (status != ComplianceStatus.compliant && reasons.isEmpty) {
      reasons.add('Could not confirm compliance from the scan.');
    }

    final tags = <String>[
      if (s.expired) 'expired',
      if (s.expirationMissing) 'no / unreadable expiration date',
      if (s.expirationUnreadable) 'unreadable expiration date',
      if (s.ingredientsMissing) 'no / unreadable ingredient list',
      if (damageFails) 'packaging damage',
    ];

    return ScanRecord(
      kind: ScanKind.both,
      status: status,
      matchedKeyword: s.advisoryFlagged
          ? _matchedLabelKeyword(s)
          : (tags.isEmpty ? '—' : tags.join(', ')),
      reasons: reasons,
      productName: s.fields.productName,
      expiration: _expirationLabel(s),
      ingredients: s.fields.ingredients,
      extractedText: combinedText,
      damageCheck: damage,
      packagingType: packagingType,
      timings: _mergeTimings(ocrTimings, damage),
      scannedAt: DateTime.now(),
    );
  }

  // ── Shared internals ──────────────────────────────────────────────────

  static Future<_LabelSignals> _computeLabelSignals({
    required Map<PhotoSlot, String> textBySlot,
    DateCode? dateCode,
    required bool expirationDeclaredMissing,
    required bool ingredientsDeclaredMissing,
    required bool ingredientsRequired,
    void Function(ScanStage stage)? onStageChange,
  }) async {
    onStageChange?.call(ScanStage.matchingRegistry);
    final LabelFields fields = LabelParser.parse(textBySlot);

    FdaAdvisoryMatch? advisoryMatch;
    if (_advisoryDatasetEnabled) {
      await FdaDatasetChecker.ensureLoaded();
      advisoryMatch =
          FdaDatasetChecker.match(textBySlot[PhotoSlot.front] ?? '');
    }
    // Names typed into the hidden debug screen, for testing the Warning path.
    // Independent of the flag above: an entry only exists if someone added it.
    if (advisoryMatch == null) {
      await DebugAdvisories.instance.ensureLoaded();
      advisoryMatch =
          DebugAdvisories.instance.match(textBySlot[PhotoSlot.front] ?? '');
    }

    onStageChange?.call(ScanStage.classifying);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // The structured read wins when the expiration slot produced one: it knows
    // which printed value is the expiry rather than taking the first date it
    // finds, and it can say "I could not read this" as its own answer.
    final DateTime? expiryDate = dateCode != null
        ? dateCode.expiry
        : fields.expirationDate;
    final bool expired = expiryDate != null && today.isAfter(expiryDate);

    // A code that could not be read is NOT the same as a product with no
    // expiry problem. Letting it fall through as a pass is what inflates the
    // clean counts, so it fails the scan on its own terms — unless the user
    // has already verified there is no date printed at all, which is the
    // separate expirationMissing outcome.
    final bool expirationUnreadable = dateCode != null &&
        dateCode.status == DateCodeStatus.unreadable &&
        !expirationDeclaredMissing;
    // The user can verify on-camera that an element simply isn't printed on the
    // packaging; that declaration alone fails compliance (the label is absent),
    // independent of whatever OCR did or didn't read.
    //
    // Only where the packaging is expected to carry one at all — see
    // PackagingTypeX.requiresIngredientList. Clearing the flag here, at the
    // source, keeps the verdict, the reasons, the tags and the matched-keyword
    // line consistent with each other, rather than patching each consumer.
    final bool ingredientsMissing = ingredientsRequired &&
        (ingredientsDeclaredMissing || !fields.ingredientsPresent);

    return _LabelSignals(
      fields: fields,
      advisoryMatch: advisoryMatch,
      advisoryFlagged: advisoryMatch != null,
      expired: expired,
      expirationMissing: expirationDeclaredMissing,
      expirationUnreadable: expirationUnreadable,
      dateCode: dateCode,
      ingredientsMissing: ingredientsMissing,
    );
  }

  static Future<DamageCheckResult> _computeDamage(
      PackagingType packagingType,
      List<String> boxPhotoPaths,
      List<String>? boxPhotoLabels,
      void Function(ScanStage stage)? onStageChange,
      ) async {
    onStageChange?.call(ScanStage.checkingDamage);
    return PackagingDamageService.check(packagingType, boxPhotoPaths,
        photoLabels: boxPhotoLabels);
  }

  /// One timing list for a scan that ran both halves: the OCR stages measured
  /// at capture time plus whatever the damage detector measured for itself.
  static ScanTimings _mergeTimings(
      ScanTimings ocrTimings, DamageCheckResult damage) {
    if (damage.timings.isEmpty) return ocrTimings;
    if (ocrTimings.isEmpty) return damage.timings;
    final builder = ScanTimingsBuilder()
      ..addAll(ocrTimings)
      ..addAll(damage.timings);
    return builder.build();
  }

  static bool _damageFails(DamageCheckResult damage) =>
      damage.available &&
          damage.isDamaged &&
          damage.maxConfidence >= damageConfidenceThreshold;

  /// Throws [DamageCheckUnavailable] unless the damage check is in a position
  /// to give a verdict.
  ///
  /// It is when it ran at all, and then either found damage bad enough to
  /// fail the scan — a defect on one photo is a defect whatever happened to
  /// the others — or got through every photo. A photo the model could not
  /// process is a side of the packaging nobody looked at, so the rest coming
  /// back clean is not enough to call the packaging compliant.
  static void _requireDamageVerdict(
      DamageCheckResult damage, bool damageFails) {
    if (!damage.available) throw DamageCheckUnavailable(damage.message);
    if (damageFails) return;
    final report = damage.report;
    final failed = report?.photosFailed ?? 0;
    if (failed > 0) {
      throw DamageCheckUnavailable(
          'The damage check could not process $failed of '
          '${report!.photosTotal} packaging photos, so the packaging was not '
          'fully inspected.');
    }
  }

  /// Names what the detector found and how sure it was, e.g.
  /// "Packaging damage — Structural deformation detected (84% confidence)."
  /// Falls back to the generic wording for records with no class list.
  static String _damageReason(DamageCheckResult damage) {
    final confidence =
        '(${(damage.maxConfidence * 100).toStringAsFixed(0)}% confidence)';
    final classes = damage.detections.toSet().toList();
    final detail = classes.isEmpty
        ? 'severe damage detected $confidence'
        : '${classes.join(', ')} detected $confidence';
    return 'Packaging damage — $detail.';
  }

  static String _matchedLabelKeyword(_LabelSignals s) {
    if (s.advisoryMatch != null) return s.advisoryMatch!.productName;
    final tags = <String>[
      if (s.expired) 'expired',
      if (s.expirationMissing) 'no / unreadable expiration date',
      if (s.expirationUnreadable) 'unreadable expiration date',
      if (s.ingredientsMissing) 'no / unreadable ingredient list',
    ];
    return tags.isEmpty ? '—' : tags.join(', ');
  }

  /// [omitFallback] skips the "could not confirm compliance" catch-all —
  /// used by [analyzeInspection], which adds its own catch-all after also
  /// considering the damage check.
  /// What the report shows for the expiration field.
  ///
  /// "Unreadable" and "Not detected" are deliberately different strings: the
  /// first means a date was photographed and could not be parsed, which fails
  /// the scan, and the second is the old fallback for a slot with no date text
  /// in it at all.
  static String _expirationLabel(_LabelSignals s) {
    final code = s.dateCode;
    if (code == null) return s.fields.expiration;
    if (code.status == DateCodeStatus.unreadable) return 'Unreadable';
    final expiry = code.expiry;
    if (expiry == null) return s.fields.expiration;
    final month = expiry.month.toString().padLeft(2, '0');
    return '${expiry.year}-$month';
  }

  static List<String> _buildLabelReasons({
    required ComplianceStatus status,
    required _LabelSignals s,
    bool omitFallback = false,
  }) {
    if (status == ComplianceStatus.compliant) return const [];

    if (status == ComplianceStatus.warning) {
      if (s.advisoryMatch?.advisoryNumber == DebugAdvisories.advisoryNumber) {
        return [
          '${DebugAdvisories.reasonPrefix} added on this phone: '
              '"${s.advisoryMatch!.productName}". Not a real FDA advisory.',
        ];
      }
      return [
        'Matches FDA ${s.advisoryMatch!.advisoryNumber} (${s.advisoryMatch!.category}): '
            '"${s.advisoryMatch!.productName}".',
        'Product should not be sold or consumed. Report to the FDA hotline.',
      ];
    }

    // Non-compliant: list each failing label check.
    final reasons = <String>[];
    if (s.expired) {
      reasons.add('Expired — the printed expiration date '
          '(${s.fields.expiration}) has passed.');
    }
    if (s.expirationMissing) {
      reasons.add('No / unreadable expiration date — the user reported that '
          'the packaging carries no expiration date, or one that cannot be '
          'read.');
    }
    if (s.expirationUnreadable) {
      final note = s.dateCode?.note;
      reasons.add('The expiration date could not be read from the photo, so '
          'it could not be checked${note == null ? '' : ' — $note'}');
    }
    if (s.ingredientsMissing) {
      reasons.add('No / unreadable ingredient list — none was detected on the '
          'label, or the user reported that the packaging carries none. A box '
          'or bottle has to carry one when it is the product\'s only primary '
          'packaging.');
    }
    if (reasons.isEmpty && !omitFallback) {
      reasons.add('Could not confirm compliance from the scanned label.');
    }
    return reasons;
  }
}

/// Intermediate label-side signals shared by [ComplianceEngine.analyzeLabel]
/// and [ComplianceEngine.analyzeInspection].
class _LabelSignals {
  final LabelFields fields;
  final FdaAdvisoryMatch? advisoryMatch;
  final bool advisoryFlagged;
  final bool expired;
  final bool expirationMissing;

  /// The date code was photographed but could not be read. Distinct from
  /// [expirationMissing], which means the user verified none is printed.
  final bool expirationUnreadable;

  final bool ingredientsMissing;
  final DateCode? dateCode;

  const _LabelSignals({
    required this.fields,
    required this.advisoryMatch,
    required this.advisoryFlagged,
    required this.expired,
    required this.expirationMissing,
    this.expirationUnreadable = false,
    required this.ingredientsMissing,
    this.dateCode,
  });
}