import 'package:flutter/material.dart';
import '../models/scan_record.dart';
import '../theme/app_colors.dart';
import '../widgets/instruction_banner.dart';
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
/// Matches HomeScreen's card treatment: an instruction banner up top, then
/// three cards that each size to their own text, in a scroll view. A short
/// list of photo tips sits below the cards, shown before the camera rather
/// than after a bad scan, since framing is what the damage check is most
/// sensitive to.
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
                fontSize: 12,
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              const InstructionBanner(
                text: 'Point your camera at the packaging and take a photo '
                    'of each side we ask for.',
              ),
              const SizedBox(height: 12),
              for (final type in PackagingType.values) ...[
                _PackagingCard(
                  type: type,
                  onTap: () => _openCamera(context, type),
                ),
                if (type != PackagingType.values.last)
                  const SizedBox(height: 10),
              ],
              const SizedBox(height: 14),
              const _CaptureTips(),
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

  // Kept short on purpose — each card is only as tall as its own text, so
  // a long paragraph here makes one card visibly taller than the others.
  String get _description {
    switch (type) {
      case PackagingType.box:
        return 'Photograph the box from four sides — we\'ll scan for dents '
            'or scratches using the on-device model.';
      case PackagingType.foil:
        return 'Photograph foil packaging (sachets, blister packs) from '
            'four sides. Capture flow ready; detection model coming soon.';
      case PackagingType.bottle:
        return 'Photograph the bottle from four sides. Capture flow ready; '
            'detection model coming soon.';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Card height follows its content — the cards no longer split the
    // screen evenly, so a short description gives a short card.
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.damageKind.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                  Icon(type.icon, color: AppColors.damageKind, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    type.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                      height: 1.1,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: AppColors.accentLight, size: 20),
              ],
            ),
            if (!type.hasModel) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Coming soon',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _description,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.muted,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plain-language photo tips, shown under the packaging cards. Worded for
/// pharmacy staff and shoppers rather than developers, so there is no
/// mention of models, confidence, or detection classes here.
class _CaptureTips extends StatelessWidget {
  const _CaptureTips();

  /// Kept to one line each on purpose: five wrapped tips push this screen
  /// past the fold, and a tip nobody reads is worse than a short one.
  static const List<(IconData, String)> _tips = [
    (Icons.wb_sunny_outlined, 'Bright light, no shadows on the pack.'),
    (Icons.crop_free, 'Get close so the pack fills the photo.'),
    (Icons.layers_clear_outlined, 'Use a plain, empty background.'),
    (Icons.flare_outlined, 'Tilt shiny packs away from glare.'),
    (Icons.back_hand_outlined, 'Hold it by the edges, not the damage.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates_outlined,
                  color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              const Text(
                'For the clearest photos',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _tips.length; i++) ...[
            if (i != 0) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(_tips[i].$1,
                      color: AppColors.accentLight, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _tips[i].$2,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}