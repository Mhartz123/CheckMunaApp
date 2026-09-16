/// Measured wall-clock cost of the machine-learning work in one scan, so the
/// app can show — and each saved record can keep — how long OCR and the
/// damage model actually took on the device that ran them.
///
/// Every number here is measured on-device at scan time. Nothing is estimated
/// and nothing is measured on a desktop: a phone's thermal state, its CPU, and
/// the photo's resolution all move these figures, which is exactly why they
/// are recorded per scan rather than quoted once.
///
/// Collected by [ScanTimingsBuilder] (see CameraScreen for the OCR side and
/// DamageDetectionService for the model side), attached to `ScanRecord`, and
/// rendered by `TimingBreakdown`.
library;

/// Which part of the pipeline a [TimedStage] belongs to. Drives the grouping
/// (and group subtotals) in the UI.
enum TimingGroup { ocr, damageModel }

extension TimingGroupX on TimingGroup {
  /// Section heading shown above this group's stages.
  String get label {
    switch (this) {
      case TimingGroup.ocr:
        return 'Text recognition (ML Kit)';
      case TimingGroup.damageModel:
        return 'Damage model (YOLO, ONNX)';
    }
  }
}

/// One measured stage, e.g. "Inference" over four packaging photos.
///
/// [runs] is how many times the stage ran inside this scan — three label
/// crops for OCR, four packaging photos for the damage model — so [meanMs]
/// is the per-item cost and [totalMs] what the user actually waited.
class TimedStage {
  final TimingGroup group;
  final String label;
  final double totalMs;
  final int runs;

  const TimedStage({
    required this.group,
    required this.label,
    required this.totalMs,
    this.runs = 1,
  });

  /// Cost per run. Equal to [totalMs] for a single-run stage.
  double get meanMs => runs <= 1 ? totalMs : totalMs / runs;

  TimedStage plus(TimedStage other) => TimedStage(
        group: group,
        label: label,
        totalMs: totalMs + other.totalMs,
        runs: runs + other.runs,
      );

  Map<String, dynamic> toJson() => {
        'group': group.name,
        'label': label,
        'totalMs': totalMs,
        'runs': runs,
      };

  static TimedStage? fromJson(Map<String, dynamic> json) {
    final label = json['label'] as String?;
    final ms = (json['totalMs'] as num?)?.toDouble();
    if (label == null || ms == null) return null;
    final groupName = json['group'] as String?;
    final group = TimingGroup.values.firstWhere(
      (g) => g.name == groupName,
      orElse: () => TimingGroup.ocr,
    );
    return TimedStage(
      group: group,
      label: label,
      totalMs: ms,
      runs: (json['runs'] as num?)?.toInt() ?? 1,
    );
  }
}

/// The stages measured during one scan, in the order they ran.
class ScanTimings {
  final List<TimedStage> stages;

  const ScanTimings(this.stages);

  /// What a record carries when it was saved before timings were measured, or
  /// for a flow that measured nothing. Renders as no timing section at all —
  /// deliberately not as "0 ms", which would read as a measurement.
  static const ScanTimings empty = ScanTimings(<TimedStage>[]);

  bool get isEmpty => stages.isEmpty;
  bool get isNotEmpty => stages.isNotEmpty;

  /// Total measured ML time for the scan. Not the same as the wall time the
  /// user waited: photo I/O, UI frames, and the registry match sit outside
  /// these stages.
  double get totalMs =>
      stages.fold(0.0, (sum, s) => sum + s.totalMs);

  List<TimedStage> stagesIn(TimingGroup group) =>
      stages.where((s) => s.group == group).toList(growable: false);

  double totalMsIn(TimingGroup group) =>
      stagesIn(group).fold(0.0, (sum, s) => sum + s.totalMs);

  /// The groups present, in enum order, so the UI can skip empty sections.
  List<TimingGroup> get groups => TimingGroup.values
      .where((g) => stages.any((s) => s.group == g))
      .toList(growable: false);

  List<Map<String, dynamic>> toJson() =>
      stages.map((s) => s.toJson()).toList();

  factory ScanTimings.fromJson(List? json) {
    if (json == null || json.isEmpty) return empty;
    final stages = <TimedStage>[];
    for (final entry in json) {
      if (entry is! Map) continue;
      final stage = TimedStage.fromJson(Map<String, dynamic>.from(entry));
      if (stage != null) stages.add(stage);
    }
    return ScanTimings(stages);
  }
}

/// Accumulates stage timings while a scan runs.
///
/// [add] merges into an existing stage with the same group and label rather
/// than appending a second row, so a caller can time each photo individually
/// in a loop and still end up with one "Inference, 4 runs" line.
class ScanTimingsBuilder {
  final List<TimedStage> _stages = [];

  void add(TimingGroup group, String label, double ms, {int runs = 1}) {
    if (runs <= 0) return;
    final stage =
        TimedStage(group: group, label: label, totalMs: ms, runs: runs);
    final i = _stages.indexWhere((s) => s.group == group && s.label == label);
    if (i < 0) {
      _stages.add(stage);
    } else {
      _stages[i] = _stages[i].plus(stage);
    }
  }

  /// Merges already-built timings (e.g. the damage model's, measured inside
  /// the detector) into this scan's list.
  void addAll(ScanTimings timings) {
    for (final s in timings.stages) {
      add(s.group, s.label, s.totalMs, runs: s.runs);
    }
  }

  bool get isEmpty => _stages.isEmpty;

  ScanTimings build() => _stages.isEmpty
      ? ScanTimings.empty
      : ScanTimings(List.unmodifiable(_stages));
}

/// Formats a millisecond figure for display: sub-second values stay in ms
/// (where the differences the evaluation cares about live), anything longer
/// switches to seconds so a 12-second scan doesn't read as "12184 ms".
String formatMs(double ms) {
  if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(2)} s';
  if (ms >= 100) return '${ms.round()} ms';
  return '${ms.toStringAsFixed(1)} ms';
}
