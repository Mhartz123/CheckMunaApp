import 'package:flutter/material.dart';

import '../services/app_prefs.dart';
import '../theme/app_colors.dart';

/// Data-sharing notice and consent.
///
/// Shown once during onboarding, before any scan can be taken, and again
/// whenever [AppPrefs.consentVersion] is bumped. Also reachable any time from
/// the cloud (data sharing) button on Home, where the user can change their answer.
///
/// Nothing is pre-selected. Sharing needs the user to tick that they have
/// read the notice and then tap Share; keeping scans on the device is always
/// one tap and the app works fully either way.
///
/// If you change what is collected or who can see it, update the text here
/// AND bump [AppPrefs.consentVersion] so existing users are asked again.
class ConsentScreen extends StatefulWidget {
  /// Called after the user answers during onboarding. When null the screen
  /// was pushed from Home, shows a back button, and pops itself on answer.
  final VoidCallback? onDecided;

  const ConsentScreen({super.key, this.onDecided});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _understood = false;

  bool get _isOnboarding => widget.onDecided != null;

  Future<void> _decide(SharingDecision decision) async {
    await AppPrefs.instance.setSharingDecision(decision);
    if (!mounted) return;
    if (_isOnboarding) {
      widget.onDecided!();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(decision == SharingDecision.granted
          ? 'Scan sharing is on. New saved scans will be sent to the FDA dashboard.'
          : 'Scan sharing is off. New scans stay on this device.'),
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final current = AppPrefs.instance.decision;

    return PopScope(
      // During onboarding the user must answer; there is nowhere to go back to.
      canPop: !_isOnboarding,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: _isOnboarding
            ? null
            : AppBar(
                title: Text('Data sharing',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text)),
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.text,
                elevation: 0,
              ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.privacy_tip_outlined,
                                color: AppColors.accent, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _isOnboarding
                                  ? 'Before you scan: how your scan data is used'
                                  : 'How your scan data is used',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.text,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (current != null) ...[
                        const SizedBox(height: 14),
                        _CurrentChoice(decision: current),
                      ],
                      const SizedBox(height: 18),
                      const _Section(
                        icon: Icons.cloud_upload_outlined,
                        title: 'What is shared',
                        body:
                            'If you agree, every scan you save is uploaded to an online database: '
                            'the product photos you took (label and packaging, reduced in size), '
                            'the result (Compliant / Non-Compliant / Warning) and the reasons for it, '
                            'the text read from the label, any damage the app found, the name you give '
                            'the record, and the date and time of the scan.',
                      ),
                      const _Section(
                        icon: Icons.visibility_outlined,
                        title: 'Who can see it',
                        body:
                            'Uploaded scans appear on the CheckMuna FDA monitoring dashboard, where '
                            'they are viewed by people monitoring products for the FDA. They are used '
                            'to spot unregistered, advisory-listed or damaged products in circulation.',
                      ),
                      const _Section(
                        icon: Icons.person_off_outlined,
                        title: 'What is not shared',
                        body:
                            'No account, phone number, contacts or location are collected. Photos are '
                            'only of what you point the camera at, so avoid capturing people, '
                            'documents or anything else personal in the frame.',
                      ),
                      const _WarningSection(
                        title: 'Scanning your own or unreleased products?',
                        body:
                            'Shared results can be seen by FDA monitors and a product may be flagged '
                            'or followed up — including products you make, sell, or have not released '
                            'yet. Results are automated and can be wrong. If you are testing your own '
                            'or unreleased products, keep scans on this device, or switch off sharing '
                            'for that scan when you save it.',
                      ),
                      const _Section(
                        icon: Icons.tune,
                        title: 'Your choice',
                        body:
                            'Sharing is voluntary and every feature works without it. You can change '
                            'your answer any time from the cloud (data sharing) button on Home, and switch sharing '
                            'off for any single scan when saving it. Turning sharing off stops future '
                            'uploads; scans already sent stay on the dashboard.',
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                      top: BorderSide(color: AppColors.border, width: 0.6)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => setState(() => _understood = !_understood),
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _understood,
                            activeColor: AppColors.accent,
                            onChanged: (v) =>
                                setState(() => _understood = v ?? false),
                          ),
                          Expanded(
                            child: Text(
                              'I have read this notice and understand that shared scans '
                              'are uploaded and viewed on the FDA monitoring dashboard.',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.text,
                                  height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        key: const ValueKey('consent-share'),
                        onPressed: _understood
                            ? () => _decide(SharingDecision.granted)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.surfaceAlt,
                          disabledForegroundColor: AppColors.muted,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('I agree — share my scans',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: const ValueKey('consent-decline'),
                        onPressed: () => _decide(SharingDecision.declined),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.text,
                          side: BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('No thanks — keep scans on this device',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentChoice extends StatelessWidget {
  final SharingDecision decision;

  const _CurrentChoice({required this.decision});

  @override
  Widget build(BuildContext context) {
    final on = decision == SharingDecision.granted;
    final at = AppPrefs.instance.decidedAt;
    final when = at == null
        ? ''
        : ' since ${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: on ? AppColors.compliantBg : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(on ? Icons.cloud_done_outlined : Icons.phone_android,
              size: 18, color: on ? AppColors.compliantText : AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              on
                  ? 'Currently: sharing scans with the FDA dashboard$when.'
                  : 'Currently: scans stay on this device$when.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: on ? AppColors.compliantText : AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Section({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
                const SizedBox(height: 4),
                Text(body,
                    style: TextStyle(
                        fontSize: 13, color: AppColors.muted, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningSection extends StatelessWidget {
  final String title;
  final String body;

  const _WarningSection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 20, color: AppColors.warningText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warningText)),
                const SizedBox(height: 4),
                Text(body,
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.warningText,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
