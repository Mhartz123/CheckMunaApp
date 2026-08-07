import 'package:flutter/material.dart';
import '../models/scan_record.dart';
import '../theme/app_colors.dart';
import 'camera_screen.dart';

/// Lets the user pick which kind of packaging they're checking before the
/// camera opens, for any flow that includes a damage step — standalone
/// Damage Detection or Inspection Mode. Label-only scans skip this screen
/// entirely since there's no packaging check to configure.
///
/// Only [PackagingType.box] has a real detection model wired up right now;
/// [PackagingType.foil] and [PackagingType.bottle] are shown as "Coming
/// soon" but are fully tappable — the capture flow and record storage work
/// the same for all three, so a future model just needs to be registered in
/// `packaging_damage_service.dart`.
class PackagingTypeScreen extends StatelessWidget {
  final CameraMode mode; // CameraMode.damage or CameraMode.inspection

  const PackagingTypeScreen({super.key, required this.mode});

  void _openCamera(BuildContext context, PackagingType type) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CameraScreen(mode: mode, packagingType: type),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('What are you checking?',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        elevation: 0,
        centerTitle: true,
        shape: const Border(
          bottom: BorderSide(color: AppColors.border, width: 0.6),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select the packaging type for the damage check.',
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              for (final type in PackagingType.values) ...[
                _PackagingCard(
                  type: type,
                  onTap: () => _openCamera(context, type),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PackagingCard extends StatelessWidget {
  final PackagingType type;
  final VoidCallback onTap;

  const _PackagingCard({required this.type, required this.onTap});

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
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.damageKind.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(type.icon, color: AppColors.damageKind, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(type.label,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text)),
                      if (!type.hasModel) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Coming soon',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    type.hasModel
                        ? 'Detection model ready.'
                        : 'Capture flow is ready; detection model not '
                        'trained yet.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
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