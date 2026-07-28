import 'package:flutter/material.dart';
import '../models/scan_record.dart';
import '../theme/app_colors.dart';

/// The "what damage it is, and where" block shared by the result and record
/// detail screens.
///
/// The shipped detector is single-class, so the type line reads "Damage" for
/// every finding — the useful detail it *can* give is which sides are affected,
/// how many spots, and how confident it is. If the model is retrained with
/// per-type classes, those names flow through [DamageFinding.label] and show up
/// here with no change to this widget.
class DamageFindingsBlock extends StatelessWidget {
  final DamageCheckResult damage;

  const DamageFindingsBlock({super.key, required this.damage});

  @override
  Widget build(BuildContext context) {
    final unavailable = !damage.available;
    final damaged = damage.isDamaged;

    final Color fg = damaged
        ? const Color(0xFFC62828)
        : unavailable
            ? AppColors.muted
            : const Color(0xFF2E7D32);
    final Color bg = damaged
        ? AppColors.bannedBg
        : unavailable
            ? AppColors.surfaceAlt
            : const Color(0xFFE8F5E9);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(damage.message,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
          if (damaged) ...[
            const SizedBox(height: 12),
            Text('WHAT WAS FOUND',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: fg)),
            const SizedBox(height: 6),
            for (final finding in damage.findings)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _FindingRow(finding: finding, color: fg),
              ),
            const SizedBox(height: 4),
            Text(
              '${damage.totalSpots} damage '
              '${damage.totalSpots == 1 ? 'spot' : 'spots'} across '
              '${damage.findings.map((f) => f.slot).toSet().length} '
              'side(s): ${damage.affectedSides}.',
              style: TextStyle(fontSize: 12, color: fg),
            ),
          ],
        ],
      ),
    );
  }
}

class _FindingRow extends StatelessWidget {
  final DamageFinding finding;
  final Color color;

  const _FindingRow({required this.finding, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 3),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            finding.slot.sideName,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${finding.label} · '
            '${finding.spotCount} ${finding.spotCount == 1 ? 'spot' : 'spots'} · '
            '${(finding.confidence * 100).toStringAsFixed(0)}% confidence',
            style: TextStyle(fontSize: 12.5, color: color),
          ),
        ),
      ],
    );
  }
}

/// The label report's headline yes/no: were all required label elements
/// (product name, expiration date, ingredient list) present on the packaging?
class LabelsPresentBadge extends StatelessWidget {
  final bool allPresent;

  const LabelsPresentBadge({super.key, required this.allPresent});

  @override
  Widget build(BuildContext context) {
    final Color fg =
        allPresent ? const Color(0xFF2E7D32) : AppColors.nonCompliantText;
    final Color bg =
        allPresent ? const Color(0xFFE8F5E9) : AppColors.nonCompliantBg;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            allPresent ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 18,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'All labels present: ${allPresent ? 'Yes' : 'No'}',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
