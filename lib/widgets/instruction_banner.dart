import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Light-green "how it works" strip shown above a card list — a camera icon
/// plus a one-glance instruction. Used on [HomeScreen] and
/// [PackagingTypeScreen] so each screen's cards can stay short instead of
/// re-explaining themselves at length.
class InstructionBanner extends StatelessWidget {
  final String text;

  const InstructionBanner({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.camera_alt_outlined, color: AppColors.accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.text,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}