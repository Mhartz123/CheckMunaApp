import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../theme/app_colors.dart';

/// The three compliance verdicts and what each one means for the user.
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
          label: 'Compliant',
          description:
              'The label passed every check the app runs — it matched no FDA advisory, and the expiration date and ingredient list are present and readable. This is not an FDA endorsement; follow the product instructions for proper dosage.',
        ),
        _LegendItem(
          color: Color(0xFFFF9800),
          label: 'Non-Compliant',
          description:
              'The label failed at least one check — expired, no or unreadable expiration date, no or unreadable ingredient list, or damaged packaging. Inadvisable to consume — report to the local FDA hotline.',
        ),
        _LegendItem(
          color: Color(0xFFE57373),
          label: 'Warned',
          description:
              'The product matched an FDA advisory. Needs manual checking — confirm its status with the local FDA hotline before sale or use.',
        ),
      ],
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
