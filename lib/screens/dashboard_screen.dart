import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'camera_screen.dart';

/// The Homepage tab. Replaces the old always-mounted Scan tab — Label
/// checking, Damage checking, and Inspection Mode (both, combined) are each
/// launched from here as their own pushed CameraScreen route.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  void _openCamera(BuildContext context, CameraMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CameraScreen(mode: mode)),
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

            // ── Scan options ──────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
                child: Column(
                  children: [
                    _DashboardCard(
                      icon: Icons.list_alt_outlined,
                      iconColor: AppColors.labelKind,
                      title: 'Check Labels',
                      description: 'Check product labels for compliance.',
                      onTap: () => _openCamera(context, CameraMode.label),
                    ),
                    const SizedBox(height: 12),
                    _DashboardCard(
                      icon: Icons.inventory_2_outlined,
                      iconColor: AppColors.damageKind,
                      title: 'Damage Detection',
                      description:
                      'Check product packaging for damage.',
                      onTap: () => _openCamera(context, CameraMode.damage),
                    ),
                    const SizedBox(height: 12),
                    _DashboardCard(
                      icon: Icons.manage_search,
                      iconColor: AppColors.inspection,
                      title: 'Inspection Mode',
                      description:
                      'Check product labels for compliance and '
                          'packaging for damage.',
                      onTap: () =>
                          _openCamera(context, CameraMode.inspection),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Tinted icon box — same treatment as status icons on Records
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
          ],
        ),
      ),
    );
  }
}