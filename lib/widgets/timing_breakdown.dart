import 'package:flutter/material.dart';

import '../models/scan_timings.dart';
import '../theme/app_colors.dart';

/// Shows what the ML work in one scan cost on this device: a row per measured
/// stage with its total and per-run mean, grouped into OCR and the damage
/// model, with a subtotal per group.
///
/// Renders nothing at all for a record with no timings (one saved before they
/// were measured) — an empty table of zeros would read as a measurement of
/// zero rather than as an absence.
///
/// Used on both the result screen (right after a scan) and the saved-record
/// detail screen, so a figure quoted in the evaluation can be traced back to
/// the exact record it came from.
class TimingBreakdown extends StatelessWidget {
  final ScanTimings timings;

  /// Starts collapsed on the result screen, where the verdict is what the user
  /// came for; the saved-record screen can open it directly.
  final bool initiallyExpanded;

  const TimingBreakdown({
    super.key,
    required this.timings,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    if (timings.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Theme(
        // The stock ExpansionTile draws its own divider lines and a blue
        // trailing icon, neither of which belongs inside this card.
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          unselectedWidgetColor: AppColors.muted,
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(primary: AppColors.muted),
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: Icon(Icons.timer_outlined, size: 18, color: AppColors.muted),
          title: Text(
            'PROCESSING TIME',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: AppColors.muted,
            ),
          ),
          subtitle: Text(
            '${formatMs(timings.totalMs)} of on-device ML work',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          children: [
            for (final group in timings.groups) ...[
              _groupHeader(group),
              for (final stage in timings.stagesIn(group)) _stageRow(stage),
              const SizedBox(height: 10),
            ],
            Text(
              'Measured on this device during the scan. Excludes camera '
              'capture, file I/O and the FDA registry match; the model-load '
              'line is a one-time cost per app launch, usually paid while the '
              'photos are still being taken.',
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupHeader(TimingGroup group) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              group.label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ),
          Text(
            formatMs(timings.totalMsIn(group)),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stageRow(TimedStage stage) {
    // The mean is only worth printing when it differs from the total, i.e.
    // when the stage actually ran more than once.
    final showMean = stage.runs > 1;
    return Padding(
      padding: const EdgeInsets.only(left: 10, bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              showMean ? '${stage.label} (×${stage.runs})' : stage.label,
              style: TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            showMean
                ? '${formatMs(stage.totalMs)}  ·  ${formatMs(stage.meanMs)} each'
                : formatMs(stage.totalMs),
            style: TextStyle(
              fontSize: 12.5,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}
