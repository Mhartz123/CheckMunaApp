import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onGetStarted;

  const HomeScreen({super.key, required this.onGetStarted});

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
                      const Text(
                        'CheckMuna',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Welcome!',
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
                      'Damage Detection and Inspection Mode ask for the packaging type first — Box, Foil, or Bottle — so the right check runs. Check Labels goes straight to the camera.',
                    ),
                    _Step(
                      number: '3',
                      icon: Icons.camera_alt_outlined,
                      title: 'Capture each step',
                      description:
                      'The camera walks you through the shots one at a time: three for a label check (product name, expiration date, ingredient list), four sides for a packaging check. Fit the target inside the on-screen frame before tapping the shutter — only what is inside the frame is read.',
                    ),
                    _Step(
                      number: '4',
                      icon: Icons.fact_check_outlined,
                      title: 'Read the result',
                      description:
                      'After the last shot the app analyses on its own — no button to press. It shows Compliant, Non-Compliant, or Banned, with the reasons behind the verdict.',
                    ),
                    _Step(
                      number: '5',
                      icon: Icons.folder_outlined,
                      title: 'Name and save',
                      description:
                      'Give the scan a name so you can find it later. Saved scans, with their photos, live in the Records tab — view, rename, or delete them any time.',
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
                    _ComplianceLegendItem(
                      color: const Color(0xFF4CAF50),
                      label: 'Compliant',
                      description:
                      'Product is registered and safe to consume. Follow instructions for proper dosage.',
                    ),
                    _ComplianceLegendItem(
                      color: const Color(0xFFFF9800),
                      label: 'Non-Compliant',
                      description:
                      'Product does not meet FDA standards. Inadvisable to consume — report to the local FDA hotline.',
                    ),
                    _ComplianceLegendItem(
                      color: const Color(0xFFE57373),
                      label: 'Banned / Warning',
                      description:
                      'Product is banned by the FDA. Dangerous to consume. Report immediately to the local FDA hotline.',
                    ),
                    const SizedBox(height: 24),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.phone_outlined,
                                color: AppColors.accent, size: 22),
                          ),
                          const SizedBox(width: 14),

                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('FDA Philippines Hotline',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.text)),
                              const SizedBox(height: 2),
                              Text('(02) 8807-0751',
                                  style: TextStyle(
                                      fontSize: 13, color: AppColors.muted)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

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

class _ComplianceLegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String description;

  const _ComplianceLegendItem({
    required this.color,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color)),
                const SizedBox(height: 2),
                Text(description,
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
