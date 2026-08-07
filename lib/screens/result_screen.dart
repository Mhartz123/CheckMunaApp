import 'package:flutter/material.dart';
import '../models/scan_record.dart';
import '../theme/app_colors.dart';

class ResultScreen extends StatelessWidget {
  final ScanRecord record;

  const ResultScreen({super.key, required this.record});

  String get _title {
    switch (record.kind) {
      case ScanKind.label:
        return 'Label Scan Result';
      case ScanKind.damage:
        return 'Packaging / Damage Result';
      case ScanKind.both:
        return 'Inspection Result';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompliant = record.status == ComplianceStatus.compliant;
    final isBanned = record.status == ComplianceStatus.banned;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Label compliance',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  // Status badge
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: record.statusColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          record.statusIcon,
                          color: Colors.white,
                          size: 48,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          record.statusLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Why it's non-compliant / flagged
                  if (!isCompliant && record.reasons.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isBanned
                            ? AppColors.bannedBg
                            : AppColors.nonCompliantBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: isBanned
                                    ? AppColors.bannedText
                                    : AppColors.nonCompliantText,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isBanned
                                    ? "Why it's flagged"
                                    : "Why it's non-compliant",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: isBanned
                                      ? AppColors.bannedText
                                      : AppColors.nonCompliantText,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (final reason in record.reasons)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('•  $reason',
                                  style: const TextStyle(fontSize: 13)),
                            ),
                        ],
                      ),
                    ),

                  if (!isCompliant && record.reasons.isNotEmpty)
                    const SizedBox(height: 20),

                  // ── Label details — hidden for a damage-only scan ─────
                  if (record.hasLabelData) ...[
                    Text('PRODUCT',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted)),
                    const SizedBox(height: 2),
                    Text(record.productName,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    _labeledField('EXPIRATION', record.expiration),

                    const SizedBox(height: 20),

                    // Ingredient list
                    const Text('Ingredient list',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        record.ingredients,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Packaging / damage — hidden for a label-only scan ──
                  if (record.hasDamageData) ...[
                    if (record.hasLabelData) const Divider(height: 1),
                    if (record.hasLabelData) const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Packaging / damage',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        if (record.packagingType != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              record.packagingType!.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    _DamageSection(damage: record.damageCheck),
                  ],
                ],
              ),
            ),
          ),

          // Scan again button — fixed footer
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Scan Again',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _labeledField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.muted)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13.5)),
      ],
    );
  }
}

/// Packaging damage result, from whichever `PackagingDamageDetector` handled
/// the chosen [PackagingType] (see `packaging_damage_service.dart`).
/// [DamageCheckResult.available] is false when the check couldn't run —
/// offline/backend unreachable for a live model, no model wired up yet for
/// this packaging type, or (for a label-only scan) simply never run — shown
/// as a neutral "unavailable" state distinct from a clean "no damage" pass.
class _DamageSection extends StatelessWidget {
  final DamageCheckResult damage;

  const _DamageSection({required this.damage});

  @override
  Widget build(BuildContext context) {
    final unavailable = !damage.available;
    final damaged = damage.isDamaged;

    final Color bg = damaged
        ? AppColors.nonCompliantBg
        : unavailable
        ? AppColors.surfaceAlt
        : const Color(0xFFE8F5E9);
    final Color fg = damaged
        ? AppColors.nonCompliantText
        : unavailable
        ? AppColors.muted
        : const Color(0xFF2E7D32);
    final IconData icon = unavailable
        ? Icons.help_outline
        : damaged
        ? Icons.warning_amber_rounded
        : Icons.check_circle_outline;

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
          Row(
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(
                unavailable
                    ? 'Check unavailable'
                    : damaged
                    ? 'Possible damage detected'
                    : 'No damage detected',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13.5, color: fg),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            damage.message,
            style: TextStyle(fontSize: 12.5, color: fg),
          ),
          if (damaged && damage.detections.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Detections: ${damage.detections.toSet().join(', ')}',
              style: TextStyle(fontSize: 12, color: fg),
            ),
          ],
        ],
      ),
    );
  }
}