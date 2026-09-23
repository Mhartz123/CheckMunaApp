import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/scan_record.dart';
import '../services/app_prefs.dart';
import '../theme/app_colors.dart';
import '../widgets/capture_tips.dart';
import '../widgets/theme_toggle_button.dart';
import 'camera_screen.dart';

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

    }
  }
}

class PackagingTypeScreen extends StatefulWidget {
  final CameraMode mode;

  const PackagingTypeScreen({super.key, required this.mode});

  @override
  State<PackagingTypeScreen> createState() => _PackagingTypeScreenState();
}

class _PackagingTypeScreenState extends State<PackagingTypeScreen> {
  PackagingType? _lastUsed;
  OcrMode _ocrMode = AppPrefs.instance.ocrMode;

  /// Whether this flow reads a label at all. A damage-only scan runs no OCR,
  /// so offering a reading mode there would be a control that does nothing.
  bool get _readsLabel => widget.mode != CameraMode.damage;

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

  void _setOcrMode(OcrMode mode) {
    setState(() => _ocrMode = mode);
    AppPrefs.instance.setOcrMode(mode);
  }

  void _openCamera(BuildContext context, PackagingType type) {

    _LastPackagingType.write(type);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          mode: widget.mode,
          packagingType: type,
          ocrMode: _ocrMode,
        ),
      ),
    );
  }

  String get _flowText {
    switch (widget.mode) {
      case CameraMode.inspection:
        return 'Inspection Mode: label check first, then packaging photos.';
      case CameraMode.damage:
        return 'Damage Detection: packaging photos only.';
      case CameraMode.label:
        return 'Check Labels: label photos only.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        leadingWidth: 58,
        toolbarHeight: 72,
        leading: _backButton(context),

        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('What are you checking?',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text)),
            const SizedBox(height: 2),
            Text(_flowText,
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
        actions: [

          ThemeToggleButton(),
          IconButton(
            onPressed: () => showCaptureTips(context),
            icon: const Icon(Icons.help_outline),
            color: AppColors.muted,
            iconSize: 20,
            tooltip: 'Photo tips',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  children: [

                    if (_readsLabel) ...[
                      _OcrModePicker(
                        selected: _ocrMode,
                        onChanged: _setOcrMode,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_lastUsed != null) ...[
                      const _HintBanner(
                        text: 'The highlighted card is what you checked '
                            'last.',
                      ),
                      const SizedBox(height: 16),
                    ],
                    for (final type in PackagingType.values) ...[
                      _PackagingCard(
                        type: type,
                        mode: widget.mode,
                        isLastUsed: type == _lastUsed,
                        onTap: () => _openCamera(context, type),
                      ),
                      if (type != PackagingType.values.last)
                        const SizedBox(height: 14),
                    ],
                  ],
                ),
              ),
            ),

            const _NotSureHelper(),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _backButton(BuildContext context) {
    return Center(
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.of(context).maybePop(),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(Icons.chevron_left, size: 24, color: AppColors.text),
          ),
        ),
      ),
    );
  }
}

/// Lets the user trade reading time for reading accuracy before the camera
/// opens.
///
/// Shown here rather than buried in a settings screen because this is the
/// last screen before the capture it governs, and the choice is only
/// meaningful with a specific pack in hand: a crisp carton under good light
/// reads the same either way, a dot-matrix date on foil does not.
class _OcrModePicker extends StatelessWidget {
  final OcrMode selected;
  final ValueChanged<OcrMode> onChanged;

  const _OcrModePicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.speed, size: 18, color: AppColors.muted),
              const SizedBox(width: 8),
              Text(
                'Reading mode',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final mode in OcrMode.values) ...[
                Expanded(
                  child: _ModeChip(
                    mode: mode,
                    isSelected: mode == selected,
                    onTap: () => onChanged(mode),
                  ),
                ),
                if (mode != OcrMode.values.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            selected.description,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final OcrMode mode;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    return Material(
      color: isSelected ? accent.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? accent : AppColors.border,
              width: isSelected ? 1.4 : 0.8,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16,
                color: isSelected ? accent : AppColors.muted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  mode.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? AppColors.text : AppColors.muted,
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

class _HintBanner extends StatelessWidget {
  final String text;

  const _HintBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.damageKind;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.text,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PackagingCard extends StatelessWidget {
  final PackagingType type;
  final CameraMode mode;
  final bool isLastUsed;
  final VoidCallback onTap;

  const _PackagingCard({
    required this.type,
    required this.mode,
    required this.isLastUsed,
    required this.onTap,
  });

  /// What will happen after this card is tapped. A label check photographs
  /// the label, not the packaging, so the damage-model copy would promise a
  /// scan that never runs.
  String get _description =>
      mode == CameraMode.label ? _labelDescription : _damageDescription;

  String get _labelDescription {
    switch (type) {
      case PackagingType.box:
      case PackagingType.bottle:
        return 'Photograph the product name, expiration date and ingredient '
            'list printed on the ${type.label.toLowerCase()}.';
      case PackagingType.foil:
        return 'Photograph the product name and expiration date. Foil is not '
            'required to carry an ingredient list, so a missing one is not '
            'flagged.';
    }
  }

  String get _damageDescription {
    switch (type) {
      case PackagingType.box:
        return 'Photograph the box from four sides — we\'ll scan for label '
            'aberrations or structural deformation using the on-device model.';
      case PackagingType.foil:
        return 'Photograph foil packaging (sachets, blister packs) front '
            'and back — we\'ll scan for structural deformation using the '
            'on-device model.';
      case PackagingType.bottle:
        return 'Photograph the bottle from four sides — we\'ll scan for label '
            'aberrations using the on-device model.';
    }
  }

  @override
  Widget build(BuildContext context) {

    final ready = type.hasModel;
    final tint = ready ? AppColors.damageKind : AppColors.muted;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),

            border: Border.all(
              color: isLastUsed ? AppColors.accent : AppColors.border,
              width: isLastUsed ? 1.4 : 0.8,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(type.icon, color: tint, size: 22),
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          type.label,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: ready ? AppColors.text : AppColors.muted,
                          ),
                        ),
                        if (ready)
                          _Pill(
                            text: 'READY',
                            color: AppColors.accent,
                            background:
                            AppColors.accent.withValues(alpha: 0.12),
                          ),
                        if (isLastUsed)
                          _Pill(
                            text: 'LAST USED',
                            color: AppColors.inspection,
                            background: AppColors.inspection
                                .withValues(alpha: 0.12),
                          ),
                        if (!ready)

                          _Pill(
                            text: 'SOON',
                            color: AppColors.muted,
                            background: AppColors.surfaceAlt,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _description,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.muted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }
}

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
