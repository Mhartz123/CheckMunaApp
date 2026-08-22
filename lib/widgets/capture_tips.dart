import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

const List<(IconData, String)> _tips = [
  (
  Icons.wb_sunny_outlined,
  'Find good light. A bright spot with no shadows falling across the '
      'packaging.',
  ),
  (
  Icons.crop_free,
  'Get close. The packaging should fill most of the photo.',
  ),
  (
  Icons.layers_clear_outlined,
  'Clear the background. An empty table or counter works best.',
  ),
  (
  Icons.flare_outlined,
  'Avoid shine. Tilt shiny or foil packaging so light does not bounce '
      'back at the camera.',
  ),
  (
  Icons.back_hand_outlined,
  'Hold it by the edges, so your fingers do not cover any damage.',
  ),
];

Future<void> showCaptureTips(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _CaptureTipsSheet(),
  );
}

class _CaptureTipsSheet extends StatelessWidget {
  const _CaptureTipsSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [

            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.tips_and_updates_outlined,
                    color: AppColors.accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  'For the clearest photos',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < _tips.length; i++) ...[
              if (i != 0) const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(_tips[i].$1,
                        color: AppColors.accentLight, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _tips[i].$2,
                      style: TextStyle(
                        fontSize: 14,
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
      ),
    );
  }
}
