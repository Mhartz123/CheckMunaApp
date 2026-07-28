import 'package:flutter/material.dart';
import '../models/scan_record.dart';
import '../theme/app_colors.dart';

/// One news/advisory item. These are placeholder entries for now — the app has
/// no live feed into the FDA Philippines site yet, so the list below is static
/// demo content flagged as such in the UI.
typedef _NewsItem = ({
  String tag,
  String title,
  String summary,
  String date,
});

const List<_NewsItem> _fillerNews = [
  (
    tag: 'ADVISORY',
    title: 'FDA warns public against unregistered food supplements',
    summary:
        'The FDA reminds consumers to check for a valid Certificate of Product '
        'Registration before buying supplements sold online. Unregistered '
        'products have not undergone safety and quality evaluation.',
    date: 'Jul 09, 2026',
  ),
  (
    tag: 'RECALL',
    title: 'Voluntary recall of select canned goods over labeling defect',
    summary:
        'A manufacturer has issued a voluntary recall after a batch shipped '
        'with incomplete expiration and allergen information. Affected lot '
        'numbers are listed on the official bulletin.',
    date: 'Jul 05, 2026',
  ),
  (
    tag: 'GUIDANCE',
    title: 'Updated rules on nutrition facts labeling now in effect',
    summary:
        'New formatting requirements for serving size and added sugars apply to '
        'prepackaged food. Businesses are given a transition period to update '
        'existing packaging.',
    date: 'Jun 28, 2026',
  ),
  (
    tag: 'ADVISORY',
    title: 'Reminder: verify cosmetics notification numbers',
    summary:
        'Cosmetic products must carry a valid notification number. The FDA '
        'encourages the public to report items making misleading therapeutic '
        'claims.',
    date: 'Jun 21, 2026',
  ),
  (
    tag: 'NEWS',
    title: 'FDA expands online verification portal for registered products',
    summary:
        'Consumers can now search a wider catalog of registered food, drug, and '
        'household products directly from their phones to confirm authenticity.',
    date: 'Jun 14, 2026',
  ),
];

class NewsScreen extends StatelessWidget {
  /// Opens the camera in the chosen inspection mode. The two entry buttons at
  /// the top of this screen are the app's main way in — label compliance and
  /// physical damage are separate checks and never run together.
  final ValueChanged<ScanType> onStartScan;
  final VoidCallback onRecordsTap;

  const NewsScreen({
    super.key,
    required this.onStartScan,
    required this.onRecordsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  bottom: BorderSide(color: AppColors.border, width: 0.6),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Label Check',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                  Icon(Icons.notifications_none,
                      color: AppColors.muted, size: 22),
                ],
              ),
            ),

            // ── Body ──────────────────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                children: [
                  // ── The two inspections ────────────────────────────────
                  Text(
                    'Start a check',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentLight,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _CheckButton(
                    icon: Icons.fact_check_outlined,
                    title: 'Label Check',
                    subtitle:
                        'Photograph the product name, expiration date and '
                        'ingredient list to verify the label.',
                    color: AppColors.accentLight,
                    onTap: () => onStartScan(ScanType.label),
                  ),
                  const SizedBox(height: 10),
                  _CheckButton(
                    icon: Icons.broken_image_outlined,
                    title: 'Physical Damage Check',
                    subtitle:
                        'Photograph all four sides of the box to inspect the '
                        'packaging for damage.',
                    color: const Color(0xFF1E88E5),
                    onTap: () => onStartScan(ScanType.damage),
                  ),
                  const SizedBox(height: 22),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'FDA Philippines · Latest',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accentLight,
                          letterSpacing: 0.4,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Demo content',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  for (final item in _fillerNews) ...[
                    _NewsCard(item: item),
                    const SizedBox(height: 12),
                  ],

                  const SizedBox(height: 2),

                  // Shortcut to saved reports
                  _ShortcutButton(
                    icon: Icons.list_alt_outlined,
                    label: 'Records',
                    onTap: onRecordsTap,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  final _NewsItem item;

  const _NewsCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              item.tag,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.summary,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.muted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              item.date,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A primary entry card for one of the two inspections.
class _CheckButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _CheckButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.45), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ShortcutButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.accent, size: 22),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
