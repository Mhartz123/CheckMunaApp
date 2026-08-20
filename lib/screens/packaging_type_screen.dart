import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/scan_record.dart';
import '../theme/app_colors.dart';
import '../widgets/capture_tips.dart';
import '../widgets/theme_toggle_button.dart';
import 'camera_screen.dart';

/// Remembers which packaging type was picked last, so a user working
/// through a shelf of the same product form does not re-decide every time.
///
/// Stored as a one-line file in the app documents directory rather than in
/// shared_preferences, since path_provider is already a dependency and this
/// is a single value. A missing or unreadable file just means "no last
/// choice" — it is a convenience, so it never blocks the screen.
class _LastPackagingType {
  static const String _fileName = 'last_packaging_type.txt';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  static Future<PackagingType?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final name = (await file.readAsString()).trim();
      for (final type in PackagingType.values) {
        if (type.name == name) return type;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(PackagingType type) async {
    try {
      final file = await _file();
      await file.writeAsString(type.name);
    } catch (_) {
      // Not worth surfacing — the next screen still opens correctly.
    }
  }
}

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
/// Matches HomeScreen's card treatment: three cards that each size to their
/// own text, in a scroll view. A line above them names which flow the user
/// is in, since this screen otherwise looks identical whether it was
/// reached from Damage Detection or Inspection Mode. Photo tips live behind
/// the help icon in the app bar rather than taking up space on the screen.
///
/// Reached only via `Navigator.push` from the Homepage — never a
/// permanently mounted tab — so unlike DashboardScreen/RecordsScreen, a
/// `const` custom widget here is never at risk of going stale after a theme
/// toggle: this whole screen is always freshly built after the current
/// theme is already set, since the toggle itself only lives on the
/// Homepage. `const _NotSureHelper()` and `const _PackagingGuideSheet()`
/// below are left const on purpose for that reason.
class PackagingTypeScreen extends StatefulWidget {
  final CameraMode mode; // CameraMode.damage or CameraMode.inspection

  const PackagingTypeScreen({super.key, required this.mode});

  @override
  State<PackagingTypeScreen> createState() => _PackagingTypeScreenState();
}

class _PackagingTypeScreenState extends State<PackagingTypeScreen> {
  PackagingType? _lastUsed;

  @override
  void initState() {
    super.initState();
    _loadLastUsed();
  }

  Future<void> _loadLastUsed() async {
    final type = await _LastPackagingType.read();
    if (!mounted) return;
    setState(() => _lastUsed = type);
  }

  void _openCamera(BuildContext context, PackagingType type) {
    // Recorded on the way out rather than after a successful save: the
    // marker reflects what was last picked here, not what was last scanned.
    _LastPackagingType.write(type);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CameraScreen(mode: widget.mode, packagingType: type),
      ),
    );
  }

  /// Names the flow the user came in on. Inspection Mode reaches this screen
  /// after the label step is already queued up, which is worth saying — the
  /// two flows are otherwise indistinguishable from here.
  String get _flowText {
    switch (widget.mode) {
      case CameraMode.inspection:
        return 'Inspection Mode: label check first, then packaging photos.';
      case CameraMode.damage:
        return 'Damage Detection: packaging photos only.';
      case CameraMode.label:
      // Label-only never routes here, but the switch has to be total.
        return 'Label check.';
    }
  }

  IconData get _flowIcon => widget.mode == CameraMode.inspection
      ? Icons.manage_search
      : Icons.inventory_2_outlined;

  Color get _flowColor => widget.mode == CameraMode.inspection
      ? AppColors.inspection
      : AppColors.damageKind;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        // Was `const Text(...)` — dropped since AppColors.text now varies
        // with the theme toggle.
        title: Text('What are you checking?',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text)),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        elevation: 0,
        centerTitle: true,
        actions: [
          // Theme toggle here as well as on the Homepage, so switching does
          // not require backing out of the flow.
          ThemeToggleButton(),
          IconButton(
            onPressed: () => showCaptureTips(context),
            icon: const Icon(Icons.help_outline),
            color: AppColors.muted,
            iconSize: 20,
            tooltip: 'Photo tips',
          ),
        ],
        // Was `const Border(...)` — dropped since AppColors.border now
        // varies with the theme toggle.
        shape: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.6),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              _FlowLine(
                icon: _flowIcon,
                color: _flowColor,
                text: _flowText,
                // Only worth saying once a highlight is actually on screen.
                note: _lastUsed == null
                    ? null
                    : 'The highlighted card is what you checked last.',
              ),
              const SizedBox(height: 12),
              for (final type in PackagingType.values) ...[
                _PackagingCard(
                  type: type,
                  isLastUsed: type == _lastUsed,
                  onTap: () => _openCamera(context, type),
                ),
                if (type != PackagingType.values.last)
                  const SizedBox(height: 16),
              ],
              const SizedBox(height: 18),
              const _NotSureHelper(),
            ],
          ),
        ),
      ),
    );
  }
}

/// One-line reminder of which scan the user started. Tinted to match the
/// flow's colour on the Homepage cards, so the two read as the same thing.
class _FlowLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  /// Optional second line, dimmer than [text]. Used to explain the
  /// last-used highlight, which is otherwise unlabelled decoration.
  final String? note;

  const _FlowLine({
    required this.icon,
    required this.color,
    required this.text,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  // Was `const TextStyle` — dropped since AppColors.text
                  // now varies with the theme toggle.
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.text,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    note!,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PackagingCard extends StatelessWidget {
  final PackagingType type;
  final bool isLastUsed;
  final VoidCallback onTap;

  const _PackagingCard({
    required this.type,
    required this.isLastUsed,
    required this.onTap,
  });

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
          // The order of the three cards never changes, so the last-used
          // one is marked in place rather than moved to the top — a picker
          // that reorders itself makes the choice harder, not easier.
          border: isLastUsed
              ? Border.all(color: AppColors.accent.withValues(alpha: 0.45))
              : null,
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
                    // Was `const TextStyle` — dropped since AppColors.text
                    // now varies with the theme toggle.
                    style: TextStyle(
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
            if (isLastUsed || !type.hasModel) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (isLastUsed)
                    _Pill(
                      text: 'Last used',
                      color: AppColors.accent,
                      background: AppColors.accent.withValues(alpha: 0.10),
                    ),
                  if (!type.hasModel)
                  // Was `const _Pill(...)` — this one is a genuine
                  // compile error once AppColors stops being const, not
                  // just a staleness risk: `color`/`background` here are
                  // constructor *arguments*, and every argument to a
                  // `const` constructor call must itself be a
                  // compile-time constant.
                    _Pill(
                      text: 'Coming soon',
                      color: AppColors.muted,
                      background: AppColors.surfaceAlt,
                    ),
                ],
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

/// Small rounded label. Two can sit side by side on one card (a last-used
/// Foil or Bottle shows both), which is why they live in a Wrap.
class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;

  const _Pill({
    required this.text,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// "Not sure which one?" — opens a short guide to picking a packaging type.
/// Exists because the three labels are not as self-evident as they look: a
/// bottle inside a carton fits two of them, and users currently just guess.
class _NotSureHelper extends StatelessWidget {
  const _NotSureHelper();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showGuide(context),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.help_outline, color: AppColors.accent, size: 16),
            const SizedBox(width: 8),
            Text(
              'Not sure which one?',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _showGuide(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _PackagingGuideSheet(),
    );
  }
}

class _PackagingGuideSheet extends StatelessWidget {
  const _PackagingGuideSheet();

  /// One rule per type, plus the two cases that actually confuse people.
  /// Deliberately phrased around what the user is holding, not around what
  /// the product is called.
  static const List<(PackagingType, String)> _rules = [
    (
    PackagingType.box,
    'Anything in a cardboard carton, even if there is a bottle or foil '
        'inside it. Photograph the carton.',
    ),
    (
    PackagingType.foil,
    'Blister packs and sachets. The tablets are sealed into the sheet '
        'itself.',
    ),
    (
    PackagingType.bottle,
    'Plastic or glass containers with a cap, whether it holds tablets, '
        'powder, or liquid.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
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
            // Was `const Text(...)` — dropped since AppColors.text now
            // varies with the theme toggle.
            Text(
              'Which one am I holding?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < _rules.length; i++) ...[
              if (i != 0) const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.damageKind.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_rules[i].$1.icon,
                        color: AppColors.damageKind, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _rules[i].$1.label,
                          // Was `const TextStyle` — dropped since
                          // AppColors.text now varies with the theme toggle.
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _rules[i].$2,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.muted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Still unsure? Pick whichever describes the outside of what '
                    'you are holding. That is the surface you will be '
                    'photographing.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.text,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}