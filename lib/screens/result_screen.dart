import 'package:flutter/material.dart';
import '../models/scan_record.dart';
import '../theme/app_colors.dart';
import '../widgets/damage_findings.dart';

/// Post-scan result. The two inspections report entirely different things, so
/// this screen branches on [ScanRecord.type] rather than showing one combined
/// layout with half the fields blank.
class ResultScreen extends StatelessWidget {
  final ScanRecord record;

  const ResultScreen({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final isLabel = record.isLabelCheck;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(isLabel ? 'Label Check Result' : 'Damage Check Result'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: isLabel ? _labelBody() : _damageBody(),
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
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Label check ────────────────────────────────────────────────────────────

  Widget _labelBody() {
    final isCompliant = record.status == ComplianceStatus.compliant;
    final isBanned = record.status == ComplianceStatus.banned;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Label compliance',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
              Icon(record.statusIcon, color: Colors.white, size: 48),
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
        if (!isCompliant) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:
                  isBanned ? AppColors.bannedBg : AppColors.nonCompliantBg,
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
                      isBanned ? "Why it's flagged" : "Why it's non-compliant",
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
          const SizedBox(height: 20),
        ],

        // The three reported label fields
        Text('PRODUCT',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.muted)),
        const SizedBox(height: 2),
        Text(record.productName,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        _labeledField('EXPIRATION DATE', record.expiration),
        const SizedBox(height: 14),
        LabelsPresentBadge(allPresent: record.allLabelsPresent),

        const SizedBox(height: 20),

        // Ingredient list
        const Text('Ingredient list',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child:
              Text(record.ingredients, style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  // ── Damage check ───────────────────────────────────────────────────────────

  Widget _damageBody() {
    final damage = record.damageCheck;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Physical damage',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        // Damaged / not damaged badge — damage checks don't carry the FDA
        // compliance wording.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: record.damageColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(record.damageIcon, color: Colors.white, size: 48),
              const SizedBox(height: 8),
              Text(
                record.damageTitle.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        DamageFindingsBlock(damage: damage),
      ],
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
