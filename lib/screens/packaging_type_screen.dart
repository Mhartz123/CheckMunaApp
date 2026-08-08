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
///
/// Matches DashboardScreen's card treatment: exactly three big cards, each
/// an equal share of the available height, no scrolling.
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
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.text)),
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
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              for (final type in PackagingType.values) ...[
                _PackagingCard(
                  type: type,
                  onTap: () => _openCamera(context, type),
                ),
                if (type != PackagingType.values.last)
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

  String get _description {
    switch (type) {
      case PackagingType.box:
        return 'Photograph the box from four sides and we\'ll scan for '
            'dents or scratches using the on-device detection model.';
      case PackagingType.foil:
        return 'Photograph foil packaging — sachets, blister packs, and '
            'similar — from four sides. The capture flow is ready; the '
            'detection model for this packaging type hasn\'t been trained '
            'yet.';
      case PackagingType.bottle:
        return 'Photograph the bottle from four sides. The capture flow is '
            'ready; the detection model for this packaging type hasn\'t '
            'been trained yet.';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Expanded so three cards in a Column split the available height evenly
    // — matches DashboardScreen's non-scrolling treatment.
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
                      color: AppColors.damageKind.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(type.icon,
                        color: AppColors.damageKind, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      type.label,
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
              if (!type.hasModel) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Coming soon',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: Text(
                  _description,
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