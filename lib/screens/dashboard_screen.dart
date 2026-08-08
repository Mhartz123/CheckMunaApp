import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'camera_screen.dart';
import 'packaging_type_screen.dart';

/// The Homepage tab. Replaces the old always-mounted Scan tab — Label
/// checking opens the camera directly; Damage Detection and Inspection Mode
/// first go through PackagingTypeScreen to pick Box/Foil/Bottle, since both
/// include a damage step.
///
/// Cards are big and non-scrolling by design: exactly three of them, each
/// taking an equal share of the available height below the header, so the
/// whole screen fills without a scroll gesture.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  void _openLabelCamera(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CameraScreen(mode: CameraMode.label),
      ),
    );
  }

  void _openPackagingPicker(BuildContext context, CameraMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PackagingTypeScreen(mode: mode)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header — same bar treatment as Records/News ──────────
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  bottom: BorderSide(color: AppColors.border, width: 0.6),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.accentLight,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.qr_code_scanner,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'VerifyDA',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ),

            // ── Scan options — fills remaining space, no scroll ────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _DashboardCard(
                      icon: Icons.list_alt_outlined,
                      iconColor: AppColors.labelKind,
                      title: 'Check Labels',
                      description:
                      'Scan the front, expiration date, and ingredients '
                          'panel of a product label. We check it against the '
                          'FDA registry and flag anything expired, '
                          'unregistered, or missing required information.',
                      onTap: () => _openLabelCamera(context),
                    ),
                    const SizedBox(height: 12),
                    _DashboardCard(
                      icon: Icons.inventory_2_outlined,
                      iconColor: AppColors.damageKind,
                      title: 'Damage Detection',
                      description:
                      'Photograph packaging from multiple angles and '
                          'we\'ll scan for dents, tears, or scratches using '
                          'on-device detection — works even without an '
                          'internet connection.',
                      onTap: () =>
                          _openPackagingPicker(context, CameraMode.damage),
                    ),
                    const SizedBox(height: 12),
                    _DashboardCard(
                      icon: Icons.manage_search,
                      iconColor: AppColors.inspection,
                      title: 'Inspection Mode',
                      description:
                      'Run both checks in one pass — scan the label for '
                          'compliance and photograph the packaging for '
                          'damage, then get a single combined result.',
                      onTap: () => _openPackagingPicker(
                          context, CameraMode.inspection),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Expanded so three cards in a Column split the available height evenly
    // — this is what keeps the whole screen non-scrolling.
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: iconColor, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                        height: 1.15,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(Icons.chevron_right,
                        color: AppColors.accentLight, size: 24),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Text(
                  description,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: AppColors.muted,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}