import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/compliance_legend.dart';

/// The welcome guide.
///
/// Shown as onboarding on first launch only (with a Get Started button), and
/// re-openable any time from the Home header's legend sheet as a plain guide
/// with a close button — pass no [onGetStarted] for that mode.
class HomeScreen extends StatelessWidget {
  final VoidCallback? onGetStarted;

  const HomeScreen({super.key, this.onGetStarted});

  bool get _isOnboarding => onGetStarted != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [

            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.qr_code_scanner,
                            color: AppColors.accent, size: 28),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'CheckMuna',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (!_isOnboarding)
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                          tooltip: 'Close guide',
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _isOnboarding ? 'Welcome!' : 'Guide',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'A quick tour of the three checks and how a scan works.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How it works',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Step(
                      number: '1',
                      icon: Icons.checklist_rtl,
                      title: 'Pick a check',
                      description:
                      'Check Labels reads the printed label and verifies it against the FDA registry. Damage Detection photographs the packaging and looks for damage. Inspection Mode runs both and gives one combined result.',
                    ),
                    _Step(
                      number: '2',
                      icon: Icons.inventory_2_outlined,
                      title: 'Say what you are holding',
                      description:
                      'Every check asks for the packaging type first — Box, Foil, or Bottle — so the right check runs. Foil is not required to carry an ingredient list, so a missing one is not flagged.',
                    ),
                    _Step(
                      number: '3',
                      icon: Icons.camera_alt_outlined,
                      title: 'Capture each step',
                      description:
                      'The camera walks you through the shots one at a time: three for a label check (product name, expiration date, ingredient list), four sides for a box or bottle, front and back for foil. Fit the target inside the on-screen frame before tapping the shutter — only what is inside the frame is read. Each label step takes a quick burst of three photos (the shutter counts 1/3, 2/3, 3/3), so hold still until it finishes; the app combines the three readings so a word one photo misreads is corrected by the others.',
                    ),
                    _Step(
                      number: '4',
                      icon: Icons.fact_check_outlined,
                      title: 'Read the result',
                      description:
                      'After the last shot the app analyses on its own — no button to press. It shows Compliant, Non-Compliant, or Warning, with the reasons behind the verdict.',
                    ),
                    _Step(
                      number: '5',
                      icon: Icons.folder_outlined,
                      title: 'Name and save',
                      description:
                      'Give the scan a name so you can find it later. Saved scans, with their photos, live in the Records tab — view or delete them any time. If you agreed to share scan data, each saved scan is also sent to the FDA monitoring dashboard; you can change this from the cloud (data sharing) button on Home.',
                    ),
                    const SizedBox(height: 24),

                    Text(
                      'The two buttons in the camera',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'They look similar and sit close together, but only one of them changes your result.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ButtonNote(
                      icon: Icons.info_outline,
                      title: 'Photo tips (i)',
                      caption: 'Top of the camera. Help only.',
                      description:
                      'Opens advice on lighting, distance, and glare. It changes nothing about the scan — close it and carry on shooting.',
                    ),
                    _ButtonNote(
                      icon: Icons.report_gmailerrorred_outlined,
                      title: 'No expiration date / ingredient list on the box',
                      caption:
                      'Under the step text, on those two steps only. Changes the result.',
                      description:
                      'Tap this only when the packaging genuinely does not print that element. It skips the shot and records the element as missing, which counts against the product — a missing expiration date or ingredient list makes the scan Non-Compliant. If the text is there but hard to photograph, keep trying instead: move closer, change the frame size, or improve the light.',
                    ),
                    const SizedBox(height: 24),

                    Text(
                      'Compliance indicators',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const ComplianceLegend(),
                    const SizedBox(height: 24),
                    const FdaHotlineCard(),
                  ],
                ),
              ),
            ),

            if (_isOnboarding)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onGetStarted,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Get Started',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String number;
  final IconData icon;
  final String title;
  final String description;

  const _Step({
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 18, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ButtonNote extends StatelessWidget {
  final IconData icon;
  final String title;

  final String caption;
  final String description;

  const _ButtonNote({
    required this.icon,
    required this.title,
    required this.caption,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 18, color: AppColors.accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        caption,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.accent,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
