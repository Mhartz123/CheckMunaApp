/// Per-photo and whole-session measurements from one packaging-damage check,
/// for every packaging type (box, foil, bottle).
///
/// The timing breakdown already shows what the damage model cost, but
/// [ScanTimingsBuilder] merges repeated stages into one row — four photos come
/// out as a single "Inference, 4 runs" line with a mean. That is the right
/// summary for a user waiting on a scan and the wrong one for an evaluation,
/// which needs to see the spread across photos, not just the average, and
/// needs the confidences that produced the verdict rather than only the
/// maximum that gated it.
///
/// So this is kept alongside the timings rather than instead of them: same
/// measurements, reported per photo and per class, with nothing averaged away.
library;

import 'scan_record.dart' show DamageDetection;

/// What one packaging photo cost and what the model found on it.
class DamagePhotoReport {
  /// Position in the packaging-photo list, matching
  /// [DamageDetection.sourceIndex] and `ScanStore.boxPhotosInOrder`.
  final int index;

  /// Capture slot this photo came from ("Front", "Side"), or "Photo 2" when
  /// the caller did not name its slots.
  final String label;

  /// Decode, EXIF bake, letterbox and tensor conversion, measured wall-clock
  /// so it includes the isolate hop the user actually waits through.
  final double preprocessMs;

  /// Time inside the model itself.
  final double inferenceMs;

  /// False when this photo could not be decoded or inference failed on it. A
  /// failed photo is not a clean photo: it contributes no detections but must
  /// never be counted as evidence of no damage.
  final bool succeeded;

  /// The detections that survived the confidence filter and NMS on this photo,
  /// with non-damage classes already dropped.
  final List<DamageDetection> detections;

  const DamagePhotoReport({
    required this.index,
    required this.label,
    required this.preprocessMs,
    required this.inferenceMs,
    required this.succeeded,
    this.detections = const [],
  });

  double get totalMs => preprocessMs + inferenceMs;

  int get detectionCount => detections.length;

  bool get isClean => succeeded && detections.isEmpty;

  /// Highest confidence on this photo, or 0 when it found nothing.
  double get maxConfidence => detections.isEmpty
      ? 0
      : detections.map((d) => d.confidence).reduce((a, b) => a > b ? a : b);

  /// Mean confidence over this photo's detections, or 0 when it found nothing.
  double get meanConfidence => detections.isEmpty
      ? 0
      : detections.map((d) => d.confidence).reduce((a, b) => a + b) /
          detections.length;

  Map<String, dynamic> toJson() => {
        'index': index,
        'label': label,
        'preprocessMs': preprocessMs,
        'inferenceMs': inferenceMs,
        'succeeded': succeeded,
        'detections': detections.map((d) => d.toJson()).toList(),
      };

  factory DamagePhotoReport.fromJson(Map<String, dynamic> json) =>
      DamagePhotoReport(
        index: (json['index'] as num?)?.toInt() ?? 0,
        label: json['label'] as String? ?? 'Photo',
        preprocessMs: (json['preprocessMs'] as num?)?.toDouble() ?? 0,
        inferenceMs: (json['inferenceMs'] as num?)?.toDouble() ?? 0,
        // Records written before this field existed only ever stored photos
        // that ran, so absence means success rather than failure.
        succeeded: json['succeeded'] as bool? ?? true,
        detections: (json['detections'] as List?)
                ?.whereType<Map>()
                .map((d) =>
                    DamageDetection.fromJson(Map<String, dynamic>.from(d)))
                .toList() ??
            const [],
      );
}

/// Confidence figures for one detected class across a whole session.
class DamageClassStats {
  final String label;
  final int count;
  final double meanConfidence;
  final double maxConfidence;
  final double minConfidence;

  const DamageClassStats({
    required this.label,
    required this.count,
    required this.meanConfidence,
    required this.maxConfidence,
    required this.minConfidence,
  });
}

/// One damage check end to end: which model ran, what each photo cost, and
/// what it found.
class DamageSessionReport {
  /// What the photos show — "box", "bottle" or "foil".
  final String subject;

  /// The model asset that ran, so a figure can be traced to a specific export.
  final String modelAsset;

  /// Square input side the model was exported at.
  final int inputSize;

  /// The detector's own confidence filter. Distinct from the compliance
  /// engine's threshold: this decides what is worth reporting, the engine
  /// decides what is bad enough to fail a scan.
  final double confThreshold;

  /// One-time session load for this model, or null when it was already loaded
  /// before this scan (the usual case, since loading starts as soon as the
  /// packaging type is picked).
  final double? modelLoadMs;

  final List<DamagePhotoReport> photos;

  const DamageSessionReport({
    required this.subject,
    required this.modelAsset,
    required this.inputSize,
    required this.confThreshold,
    required this.photos,
    this.modelLoadMs,
  });

  bool get isEmpty => photos.isEmpty;

  int get photosTotal => photos.length;
  int get photosSucceeded => photos.where((p) => p.succeeded).length;
  int get photosFailed => photos.where((p) => !p.succeeded).length;
  int get photosWithDetections =>
      photos.where((p) => p.detections.isNotEmpty).length;
  int get photosClean => photos.where((p) => p.isClean).length;

  List<DamageDetection> get allDetections =>
      <DamageDetection>[for (final p in photos) ...p.detections];

  int get detectionCount => allDetections.length;

  double get totalPreprocessMs =>
      photos.fold(0.0, (sum, p) => sum + p.preprocessMs);

  double get totalInferenceMs =>
      photos.fold(0.0, (sum, p) => sum + p.inferenceMs);

  /// Inference only, averaged over the photos that actually ran — the figure
  /// to compare against a per-image latency budget.
  double get meanInferenceMs =>
      photosSucceeded == 0 ? 0 : totalInferenceMs / photosSucceeded;

  double get meanPreprocessMs =>
      photosSucceeded == 0 ? 0 : totalPreprocessMs / photosSucceeded;

  /// Fastest and slowest single inference, so the spread the mean hides is
  /// visible.
  double get minInferenceMs {
    final run = photos.where((p) => p.succeeded).toList();
    if (run.isEmpty) return 0;
    return run.map((p) => p.inferenceMs).reduce((a, b) => a < b ? a : b);
  }

  double get maxInferenceMs {
    final run = photos.where((p) => p.succeeded).toList();
    if (run.isEmpty) return 0;
    return run.map((p) => p.inferenceMs).reduce((a, b) => a > b ? a : b);
  }

  /// Everything the damage check cost this session, including the one-time
  /// model load when this scan is the one that paid it.
  double get sessionTotalMs =>
      totalPreprocessMs + totalInferenceMs + (modelLoadMs ?? 0);

  double get maxConfidence {
    final all = allDetections;
    if (all.isEmpty) return 0;
    return all.map((d) => d.confidence).reduce((a, b) => a > b ? a : b);
  }

  double get meanConfidence {
    final all = allDetections;
    if (all.isEmpty) return 0;
    return all.map((d) => d.confidence).reduce((a, b) => a + b) / all.length;
  }

  /// Per-class confidence figures, most detections first.
  List<DamageClassStats> get classStats {
    final byLabel = <String, List<double>>{};
    for (final d in allDetections) {
      byLabel.putIfAbsent(d.label, () => <double>[]).add(d.confidence);
    }
    final stats = byLabel.entries.map((e) {
      final values = e.value;
      return DamageClassStats(
        label: e.key,
        count: values.length,
        meanConfidence: values.reduce((a, b) => a + b) / values.length,
        maxConfidence: values.reduce((a, b) => a > b ? a : b),
        minConfidence: values.reduce((a, b) => a < b ? a : b),
      );
    }).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return stats;
  }

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'modelAsset': modelAsset,
        'inputSize': inputSize,
        'confThreshold': confThreshold,
        if (modelLoadMs != null) 'modelLoadMs': modelLoadMs,
        'photos': photos.map((p) => p.toJson()).toList(),
      };

  static DamageSessionReport? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final photos = (json['photos'] as List?)
            ?.whereType<Map>()
            .map((p) => DamagePhotoReport.fromJson(Map<String, dynamic>.from(p)))
            .toList() ??
        const <DamagePhotoReport>[];
    if (photos.isEmpty) return null;
    return DamageSessionReport(
      subject: json['subject'] as String? ?? '',
      modelAsset: json['modelAsset'] as String? ?? '',
      inputSize: (json['inputSize'] as num?)?.toInt() ?? 0,
      confThreshold: (json['confThreshold'] as num?)?.toDouble() ?? 0,
      modelLoadMs: (json['modelLoadMs'] as num?)?.toDouble(),
      photos: photos,
    );
  }
}
