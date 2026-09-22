import 'package:flutter/material.dart';

import '../models/damage_report.dart';
import '../models/scan_timings.dart' show formatMs;
import '../theme/app_colors.dart';

/// The damage model's confidence and latency figures for one scan, reported
/// per photo and per class rather than averaged into a single line.
///
/// Sits alongside `TimingBreakdown` rather than inside it: that widget answers
/// "what did this scan cost", pooling every stage of the pipeline, while this
/// one answers "how did the damage model behave on each photo" — the per-image
/// spread and the confidences behind the verdict, which is what an evaluation
/// needs and what a mean hides.
///
/// Renders nothing when no report was captured (a label-only scan, or a record
/// saved before reports existed).
class DamageReportView extends StatelessWidget {
  final DamageSessionReport? report;

  /// The compliance engine's damage threshold, drawn as the line a detection
  /// has to cross to fail the scan. Without it the confidences have no
  /// reference point and the table is just numbers.
  final double failThreshold;

  final bool initiallyExpanded;

  const DamageReportView({
    super.key,
    required this.report,
    required this.failThreshold,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = report;
    if (r == null || r.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          unselectedWidgetColor: AppColors.muted,
          colorScheme:
              Theme.of(context).colorScheme.copyWith(primary: AppColors.muted),
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading:
              Icon(Icons.analytics_outlined, size: 18, color: AppColors.muted),
          title: Text(
            'DAMAGE MODEL REPORT',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: AppColors.muted,
            ),
          ),
          subtitle: Text(
            '${r.detectionCount} detection${r.detectionCount == 1 ? '' : 's'} '
            'over ${r.photosTotal} photo${r.photosTotal == 1 ? '' : 's'}  ·  '
            '${formatMs(r.meanInferenceMs)} mean inference',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          children: [
            _sectionLabel('Session'),
            _statGrid(r),
            const SizedBox(height: 12),
            _sectionLabel('Per photo'),
            _photoTable(r),
            if (r.classStats.isNotEmpty) ...[
              const SizedBox(height: 12),
              _sectionLabel('Confidence by class'),
              _classTable(r),
            ],
            const SizedBox(height: 12),
            _footnote(r),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
      );

  Widget _statGrid(DamageSessionReport r) {
    final failed = r.photosFailed;
    return Column(
      children: [
        _statRow('Photos analysed',
            '${r.photosSucceeded} of ${r.photosTotal}'
            '${failed > 0 ? '  ($failed failed)' : ''}'),
        _statRow('Photos with detections',
            '${r.photosWithDetections}  ·  ${r.photosClean} clean'),
        _statRow('Detections', '${r.detectionCount}'),
        if (r.detectionCount > 0) ...[
          _statRow('Mean confidence', _pct(r.meanConfidence)),
          _statRow('Peak confidence', _pct(r.maxConfidence),
              emphasis: r.maxConfidence >= failThreshold),
        ],
        _statRow('Inference total', formatMs(r.totalInferenceMs)),
        _statRow('Inference per photo', '${formatMs(r.meanInferenceMs)} mean'),
        if (r.photosSucceeded > 1)
          _statRow('Fastest–slowest photo',
              '${formatMs(r.minInferenceMs)}–${formatMs(r.maxInferenceMs)}'),
        _statRow('Preprocessing total', formatMs(r.totalPreprocessMs)),
        if (r.modelLoadMs != null)
          _statRow('Model load (one-time)', formatMs(r.modelLoadMs!)),
        _statRow('Session total', formatMs(r.sessionTotalMs), bold: true),
      ],
    );
  }

  Widget _statRow(String label, String value,
      {bool bold = false, bool emphasis = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.muted,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Flexible and right-aligned rather than a bare Text: these values
          // vary in length ("3 of 4  (1 failed)"), and a number that cannot
          // fit has to wrap, never be clipped — a half-shown figure is worse
          // than no figure.
          Expanded(
            flex: 4,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    bold || emphasis ? FontWeight.w700 : FontWeight.w600,
                color: emphasis ? const Color(0xFFD32F2F) : AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoTable(DamageSessionReport r) {
    return Column(
      children: [
        _tableHeader(const ['Photo', 'Pre', 'Infer', 'Det', 'Max']),
        for (final p in r.photos) _photoRow(p),
      ],
    );
  }

  Widget _photoRow(DamagePhotoReport p) {
    final failed = !p.succeeded;
    final color = failed ? const Color(0xFFD32F2F) : AppColors.text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Expanded(
            flex: 30,
            child: Text(
              p.label,
              style: TextStyle(fontSize: 11.5, color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _cell(failed ? '—' : formatMs(p.preprocessMs), 20, color),
          _cell(failed ? '—' : formatMs(p.inferenceMs), 20, color),
          _cell(failed ? 'fail' : '${p.detectionCount}', 12, color),
          _cell(
            failed
                ? '—'
                : (p.detections.isEmpty ? 'clean' : _pct(p.maxConfidence)),
            18,
            color,
          ),
        ],
      ),
    );
  }

  Widget _classTable(DamageSessionReport r) {
    return Column(
      children: [
        _tableHeader(const ['Class', 'Count', 'Mean', 'Min', 'Max']),
        for (final c in r.classStats)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.5),
            child: Row(
              children: [
                Expanded(
                  flex: 36,
                  child: Text(
                    c.label,
                    style:
                        TextStyle(fontSize: 11.5, color: AppColors.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _cell('${c.count}', 14, AppColors.text),
                _cell(_pct(c.meanConfidence), 16, AppColors.text),
                _cell(_pct(c.minConfidence), 16, AppColors.text),
                _cell(_pct(c.maxConfidence), 18, AppColors.text),
              ],
            ),
          ),
      ],
    );
  }

  Widget _tableHeader(List<String> labels) {
    const flexes = [30, 20, 20, 12, 18];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              flex: i == 0 ? flexes[0] : flexes[i],
              child: Text(
                labels[i],
                textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: AppColors.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(String text, int flex, Color color) => Expanded(
        flex: flex,
        child: Text(
          text,
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 11.5, color: color),
        ),
      );

  Widget _footnote(DamageSessionReport r) {
    final model = r.modelAsset.split('/').last;
    return Text(
      '$model  ·  ${r.inputSize}×${r.inputSize} input  ·  detector keeps '
      'detections at or above ${_pct(r.confThreshold)}, and a scan fails at '
      '${_pct(failThreshold)}. Measured on this device during the scan; '
      'inference is model time only, preprocessing is decode and letterbox.',
      style: TextStyle(fontSize: 11, height: 1.35, color: AppColors.muted),
    );
  }

  static String _pct(double v) => '${(v * 100).toStringAsFixed(0)}%';
}
