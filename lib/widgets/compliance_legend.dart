import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../theme/app_colors.dart';

/// The scan results and what each one means for the user.
///
/// Every result names what it is based on — see `ScanRecordUi.statusTitle` —
/// rather than a bare "Compliant", which would read as a verdict on the whole
/// product.
///
/// Shared by the onboarding guide ([HomeScreen]) and the quick legend sheet
/// ([showLegendSheet]) so the two can never drift apart.
class ComplianceLegend extends StatelessWidget {
  const ComplianceLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _LegendItem(
          color: Color(0xFF4CAF50),
          label: 'COMPLIANT WITH FDA LABELING AND PACKAGING REQUIREMENTS',
          description:
              'No advisory match, a legible and valid expiry date, and no detected defect. This is not an FDA endorsement; follow the product instructions for proper dosage.',
        ),
        _LegendItem(
          color: Color(0xFFFF9800),
          label: 'NON-COMPLIANT BASED ON FDA LABELING REQUIREMENTS',
          description:
              'The expiry date is missing, illegible, or past — or the ingredient list is missing or illegible on a box or bottle. Inadvisable to consume — report to the local FDA hotline.',
        ),
        _LegendItem(
          color: Color(0xFFFF9800),
          label: 'NON-COMPLIANT BASED ON FDA PACKAGING REQUIREMENTS',
          description:
              'A Packaging Integrity Defect is detected. Inadvisable to consume — report to the local FDA hotline.',
        ),
        _LegendItem(
          color: Color(0xFFE57373),
          label: 'WARNING BASED ON FDA ADVISORY',
          description:
              'The product name matches an FDA advisory, recall, or unregistered-product record. Needs manual checking — confirm its status with the local FDA hotline before sale or use.',
        ),
        _LegendNote(
          'Ingredient list: required only on a box or bottle, and only when that box or bottle is the product\'s only primary packaging. Foil (sachets, blister packs) is not required to carry one, so a missing list on foil is disregarded.',
        ),
        _LegendNote(
          'A result only names what was scanned: a label check reports on labeling requirements, a damage check on packaging requirements, and Inspection Mode on both.',
        ),
        _LegendNote(
          'If the damage check cannot run, the scan is reported as a problem and gets no result at all.',
        ),
      ],
    );
  }
}

/// A rule that qualifies the results above — when a requirement applies, or
/// when no result is given at all.
class _LegendNote extends StatelessWidget {
  final String text;

  const _LegendNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.5),
      ),
    );
  }
}

/// FDA Philippines hotline card, shown under the legend.
class FdaHotlineCard extends StatelessWidget {
  const FdaHotlineCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.phone_outlined, color: AppColors.accent, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('FDA Philippines Hotline',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text)),
              const SizedBox(height: 2),
              Text('(02) 8807-0751',
                  style: TextStyle(fontSize: 13, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Quick-access legend: the verdict colours and the hotline, with a link to
/// the full guide. Reachable any time from the Home header, without going
/// back through onboarding.
Future<void> showLegendSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('Legend',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                )),
            const SizedBox(height: 2),
            Text('What each scan result means',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
            const SizedBox(height: 16),
            const ComplianceLegend(),
            const SizedBox(height: 12),
            const FdaHotlineCard(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const HomeScreen(),
                  ));
                },
                icon: Icon(Icons.menu_book_outlined, color: AppColors.accent),
                label: Text('Open the full guide',
                    style: TextStyle(
                        color: AppColors.accent, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String description;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color)),
                const SizedBox(height: 2),
                Text(description,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.muted, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
