import 'package:flutter/foundation.dart';

import '../models/scan_record.dart';
import 'damage_detection_service.dart';
import 'fda_dataset_checker.dart';
import 'label_parser.dart';
import 'onnx_semantic_matcher.dart';

/// Analysis stages for the label pipeline, surfaced as progress in the UI.
enum ScanStage { matchingRegistry, classifying }

class ComplianceEngine {
  /// The ONNX semantic matcher — removable last-ditch tier of the banned-name
  /// check. Runs only when the product-name OCR was unreliable and the dataset
  /// tier found no confident match; a hit against the FDA *warned* index means
  /// banned.
  ///
  /// NOTE: the shipped model's embeddings are collapsed (~1% Recall@1), so any
  /// scan that actually reaches it will likely be mis-flagged until the model
  /// is retrained/verified. The last-ditch gate keeps that blast radius small;
  /// set this to false to remove the tier entirely. See [OnnxSemanticMatcher].
  static const bool _semanticMatcherEnabled = true;

  /// Mean OCR confidence (per ML Kit, 0..1) on the product-name crop below
  /// which the name is treated as unreliable, opening the semantic fallback.
  static const double _lowOcrConfidenceThreshold = 0.6;

  /// Kicks off the asset loads for [type]'s pipeline early (from
  /// CameraScreen.initState) so the first scan isn't stuck paying full load
  /// latency while the user is still framing photos. Each mode only warms the
  /// models it actually uses.
  static void warmUp(ScanType type) {
    if (type == ScanType.damage) {
      // ignore: unawaited_futures
      DamageDetectionService.warmUp();
      return;
    }
    // ignore: unawaited_futures
    FdaDatasetChecker.ensureLoaded();
    if (_semanticMatcherEnabled) {
      // ignore: unawaited_futures
      OnnxSemanticMatcher.instance();
    }
  }

  /// Runs the **label compliance** inspection — the first of the app's two
  /// independent checks. No box photos and no damage detection are involved.
  ///
  ///  • **Banned (warned):** the product name is checked against the FDA
  ///    advisory/banned list — [FdaDatasetChecker] (word-overlap + fuzzy), with
  ///    [OnnxSemanticMatcher] as a removable last-ditch tier when the name OCR
  ///    was low-confidence. A hit here (and only here) means banned.
  ///  • **Otherwise non-compliant if any of:** the printed expiration date has
  ///    passed; the user verified no expiration date is printed; no ingredient
  ///    list was detected or the user verified none is printed.
  ///  • **Compliant** when none of the above fire.
  ///
  /// [textBySlot] maps each captured label [PhotoSlot] to the OCR text
  /// extracted from that slot's (guide-cropped) photo (see LabelParser).
  /// [combinedText] concatenates all label slots' text, used for the
  /// registry/name match. [ocrConfidence] is the mean ML Kit confidence (0..1)
  /// on the product-name crop (or null): it gates the last-ditch semantic tier.
  static Future<ScanRecord> analyzeLabel({
    required Map<PhotoSlot, String> textBySlot,
    required String combinedText,
    double? ocrConfidence,
    bool expirationDeclaredMissing = false,
    bool ingredientsDeclaredMissing = false,
    void Function(ScanStage stage)? onStageChange,
  }) async {
    onStageChange?.call(ScanStage.matchingRegistry);
    await FdaDatasetChecker.ensureLoaded();

    final LabelFields fields = LabelParser.parse(textBySlot);
    final FdaMatchOutcome advisoryOutcome =
        FdaDatasetChecker.matchOutcome(combinedText);
    final FdaAdvisoryMatch? advisoryMatch = advisoryOutcome.match;

    // Last-ditch semantic name check: runs ONLY when the product-name OCR was
    // unreliable *and* the dataset tier produced no confident match.
    onStageChange?.call(ScanStage.classifying);
    SemanticMatch? semanticMatch;
    final bool ocrUnreliable =
        ocrConfidence != null && ocrConfidence < _lowOcrConfidenceThreshold;
    final bool runSemantic =
        _semanticMatcherEnabled && ocrUnreliable && advisoryMatch == null;
    if (runSemantic) {
      try {
        final matcher = await OnnxSemanticMatcher.instance();
        semanticMatch = matcher.match(combinedText);
      } catch (e) {
        debugPrint('Semantic matcher unavailable: $e');
      }
    }

    // ── Combine signals into a compliance verdict ──────────────────────────
    final bool banned = advisoryMatch != null || semanticMatch != null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final bool expired =
        fields.expirationDate != null && today.isAfter(fields.expirationDate!);
    // The user can verify on-camera that an element simply isn't printed on the
    // packaging; that declaration alone fails compliance (the label is absent),
    // independent of whatever OCR did or didn't read.
    final bool expirationMissing = expirationDeclaredMissing;
    final bool ingredientsMissing =
        ingredientsDeclaredMissing || !fields.ingredientsPresent;
    final bool productNameMissing = fields.productName == 'Unknown Product';

    // The report's headline yes/no: were all three required label elements
    // found on the packaging? This is about *presence*, not validity — an
    // expiration date that is present but expired still counts as present.
    //
    // Product-name presence is reported but deliberately kept out of the
    // verdict below: an unreadable front crop is an OCR failure, not proof the
    // packaging lacks a name, and it never failed compliance before the
    // label/damage split either. So a scan whose name OCR came back empty can
    // read "Compliant" with "All labels present: No".
    final bool allLabelsPresent =
        !productNameMissing && !expirationMissing && !ingredientsMissing;

    final ComplianceStatus status = banned
        ? ComplianceStatus.banned
        : (expired || expirationMissing || ingredientsMissing)
            ? ComplianceStatus.nonCompliant
            : ComplianceStatus.compliant;

    final reasons = _buildLabelReasons(
      status: status,
      advisoryMatch: advisoryMatch,
      semanticMatch: semanticMatch,
      fields: fields,
      expired: expired,
      expirationMissing: expirationMissing,
      ingredientsDeclaredMissing: ingredientsDeclaredMissing,
      ingredientsMissing: ingredientsMissing,
    );

    return ScanRecord(
      type: ScanType.label,
      status: status,
      matchedKeyword: _matchedLabel(
        advisoryMatch: advisoryMatch,
        semanticMatch: semanticMatch,
        expired: expired,
        expirationMissing: expirationMissing,
        ingredientsMissing: ingredientsMissing,
      ),
      reasons: reasons,
      productName: fields.productName,
      expiration: fields.expiration,
      ingredients: fields.ingredients,
      allLabelsPresent: allLabelsPresent,
      extractedText: combinedText,
      damageCheck: const DamageCheckResult.placeholder(),
      scannedAt: DateTime.now(),
    );
  }

  /// Runs the **physical damage** inspection — the second of the app's two
  /// independent checks. No OCR, no FDA registry: just the box photos through
  /// the on-device YOLO11n detector.
  ///
  /// The resulting record's [ScanRecord.status] mirrors the damage outcome
  /// (damaged → non-compliant) so records can still be filtered and counted
  /// alongside label checks, but damage reports are presented in their own
  /// wording — see [ScanRecordUi.damageTitle].
  static Future<ScanRecord> analyzeDamage({
    required Map<BoxSlot, String> boxPhotoPaths,
  }) async {
    final DamageCheckResult damage =
        await DamageDetectionService.check(boxPhotoPaths);

    final bool damaged = damage.available && damage.isDamaged;

    return ScanRecord(
      type: ScanType.damage,
      status:
          damaged ? ComplianceStatus.nonCompliant : ComplianceStatus.compliant,
      matchedKeyword: damaged ? damage.damageTypes.join(', ') : '—',
      reasons: _buildDamageReasons(damage),
      productName: '—',
      expiration: '—',
      ingredients: '—',
      allLabelsPresent: false,
      extractedText: '',
      damageCheck: damage,
      scannedAt: DateTime.now(),
    );
  }

  static String _matchedLabel({
    required FdaAdvisoryMatch? advisoryMatch,
    required SemanticMatch? semanticMatch,
    required bool expired,
    required bool expirationMissing,
    required bool ingredientsMissing,
  }) {
    if (advisoryMatch != null) return advisoryMatch.productName;
    if (semanticMatch != null) {
      return '${semanticMatch.productName} '
          '(semantic match, ${(semanticMatch.score * 100).toStringAsFixed(0)}%)';
    }
    final tags = <String>[
      if (expired) 'expired',
      if (expirationMissing) 'no expiration date',
      if (ingredientsMissing) 'no ingredient list',
    ];
    return tags.isEmpty ? '—' : tags.join(', ');
  }

  static List<String> _buildLabelReasons({
    required ComplianceStatus status,
    required FdaAdvisoryMatch? advisoryMatch,
    required SemanticMatch? semanticMatch,
    required LabelFields fields,
    required bool expired,
    required bool expirationMissing,
    required bool ingredientsDeclaredMissing,
    required bool ingredientsMissing,
  }) {
    if (status == ComplianceStatus.compliant) return const [];

    if (status == ComplianceStatus.banned) {
      if (advisoryMatch != null) {
        return [
          'Matches FDA ${advisoryMatch.advisoryNumber} (${advisoryMatch.category}): '
              '"${advisoryMatch.productName}".',
          'Product should not be sold or consumed. Report to the FDA hotline.',
        ];
      }
      return [
        'Semantically matches FDA-flagged product '
            '"${semanticMatch!.productName}" '
            '(${(semanticMatch.score * 100).toStringAsFixed(0)}% similarity).',
        'Product should not be sold or consumed. Report to the FDA hotline.',
      ];
    }

    // Non-compliant: list each failing check.
    final reasons = <String>[];
    if (expired) {
      reasons.add(
          'Expired — the printed expiration date (${fields.expiration}) has passed.');
    }
    if (expirationMissing) {
      reasons.add('No expiration date is printed on the packaging '
          '(verified by the user).');
    }
    if (ingredientsMissing) {
      reasons.add(ingredientsDeclaredMissing
          ? 'No ingredient list is printed on the packaging (verified by the user).'
          : 'No ingredient list was detected on the label.');
    }
    if (reasons.isEmpty) {
      reasons.add('Could not confirm compliance from the scanned label.');
    }
    return reasons;
  }

  static List<String> _buildDamageReasons(DamageCheckResult damage) {
    if (!damage.available) return [damage.message];
    if (!damage.isDamaged) return const [];
    return [
      for (final finding in damage.findings) finding.summary,
      'Damaged packaging may compromise the product. Do not sell or consume; '
          'report to the FDA hotline.',
    ];
  }
}
