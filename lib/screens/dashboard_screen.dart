import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/scan_record.dart';
import '../services/scan_store.dart';
import '../theme/app_colors.dart';
import '../widgets/instruction_banner.dart';
import 'camera_screen.dart';
import 'packaging_type_screen.dart';
import 'record_detail_screen.dart';

/// One saved record reduced to just what the recent-scans strip draws, so
/// the strip never holds a whole [ScanRecord] (or its photos) in memory.
class _RecentScan {
  final Directory dir;
  final String name;
  final ScanRecord? record;
  final DateTime date;

  const _RecentScan({
    required this.dir,
    required this.name,
    required this.record,
    required this.date,
  });
}

/// The Homepage tab. Replaces the old always-mounted Scan tab — Label
/// checking opens the camera directly; Damage Detection and Inspection Mode
/// first go through PackagingTypeScreen to pick Box/Foil/Bottle, since both
/// include a damage step.
///
/// Below the three scan cards sits a recent-scans strip: the three newest
/// saved records, each tapping through to RecordDetailScreen. It reloads
/// whenever a pushed route pops back, so a scan saved from the camera shows
/// up without switching tabs.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// How many records the strip shows. Three is what fits below the scan
  /// cards without the page needing to scroll — raising this brings the
  /// scroll back.
  static const int _maxRecent = 3;

  List<_RecentScan> _recent = [];
  bool _loadingRecent = true;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  /// Reads every record folder, keeps the [_maxRecent] newest by scan date.
  /// Folders whose data.json is missing or corrupt still appear (using the
  /// folder's mtime), matching how RecordsScreen tolerates them.
  Future<void> _loadRecent() async {
    try {
      final dirs = await ScanStore.listRecordDirs();
      final scans = dirs.map((dir) {
        final record = ScanStore.load(dir);
        return _RecentScan(
          dir: dir,
          name: p.basename(dir.path),
          record: record,
          date: record?.scannedAt ?? dir.statSync().modified,
        );
      }).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      if (!mounted) return;
      setState(() {
        _recent = scans.take(_maxRecent).toList();
        _loadingRecent = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recent = [];
        _loadingRecent = false;
      });
    }
  }

  /// Every navigation off this screen can create or delete a record, so the
  /// strip is refreshed on the way back rather than only on first build.
  Future<void> _pushThenReload(Widget page) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
    await _loadRecent();
  }

  void _openLabelCamera(BuildContext context) {
    _pushThenReload(const CameraScreen(mode: CameraMode.label));
  }

  void _openPackagingPicker(BuildContext context, CameraMode mode) {
    _pushThenReload(PackagingTypeScreen(mode: mode));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header — same bar treatment as Records/News ──────────
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  bottom: BorderSide(color: AppColors.border, width: 0.6),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.accentLight,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.qr_code_scanner,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'VerifyDA',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ),

            // ── Scan options — each card sizes to its own content ──────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  children: [
                    const InstructionBanner(
                      text: 'Point your camera at the requested part and '
                          'take a photo — we\'ll walk you through each '
                          'step.',
                    ),
                    const SizedBox(height: 12),
                    _DashboardCard(
                      icon: Icons.list_alt_outlined,
                      iconColor: AppColors.labelKind,
                      title: 'Check Labels',
                      description:
                      'Scan a label\'s front, expiration date, and '
                          'ingredients. We check it against the FDA '
                          'registry and flag expired, unregistered, or '
                          'missing info.',
                      onTap: () => _openLabelCamera(context),
                    ),
                    const SizedBox(height: 10),
                    _DashboardCard(
                      icon: Icons.inventory_2_outlined,
                      iconColor: AppColors.damageKind,
                      title: 'Damage Detection',
                      description:
                      'Pick a packaging type — Box, Foil, or Bottle — '
                          'then photograph it from multiple angles. '
                          'On-device detection scans for dents or '
                          'scratches, no internet needed.',
                      onTap: () =>
                          _openPackagingPicker(context, CameraMode.damage),
                    ),
                    const SizedBox(height: 10),
                    _DashboardCard(
                      icon: Icons.manage_search,
                      iconColor: AppColors.inspection,
                      title: 'Inspection Mode',
                      description:
                      'Run both checks in one scan — verify the label '
                          'against the FDA registry, then photograph the '
                          'packaging for damage. Get one combined result.',
                      onTap: () => _openPackagingPicker(
                          context, CameraMode.inspection),
                    ),
                    const SizedBox(height: 12),
                    _RecentScansStrip(
                      scans: _recent,
                      loading: _loadingRecent,
                      onOpen: (scan) => _pushThenReload(
                        RecordDetailScreen(recordDir: scan.dir),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Card height follows its content — no Expanded, so a short
    // description gives a short card.
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
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
                    color: iconColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
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
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
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
/// The recent-scans strip: a section header plus up to three saved records,
/// newest first. Kept visually lighter than the scan cards above it — this
/// is a shortcut into Records, not a fourth action.
class _RecentScansStrip extends StatelessWidget {
  final List<_RecentScan> scans;
  final bool loading;
  final ValueChanged<_RecentScan> onOpen;

  const _RecentScansStrip({
    required this.scans,
    required this.loading,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    // Nothing to show and nothing to wait for — collapse entirely rather
    // than leaving an empty header behind.
    if (!loading && scans.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            'Recent scans',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
              letterSpacing: 0.2,
            ),
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < scans.length; i++) ...[
                  _RecentScanRow(
                    scan: scans[i],
                    onTap: () => onOpen(scans[i]),
                  ),
                  if (i != scans.length - 1)
                    const Divider(
                      height: 1,
                      thickness: 0.6,
                      indent: 14,
                      endIndent: 14,
                      color: AppColors.border,
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _RecentScanRow extends StatelessWidget {
  final _RecentScan scan;
  final VoidCallback onTap;

  const _RecentScanRow({required this.scan, required this.onTap});

  static String _pad(int n) => n.toString().padLeft(2, '0');

  /// Short relative date — the strip only ever shows recent records, so a
  /// full timestamp would be noise. Falls back to a calendar date once the
  /// record is old enough that "days ago" stops being readable.
  String get _when {
    final diff = DateTime.now().difference(scan.date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${scan.date.year}-${_pad(scan.date.month)}-${_pad(scan.date.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final record = scan.record;

    // A record whose data.json failed to parse still gets a row (so it's
    // discoverable and deletable from the detail screen) but no status pill.
    final statusColor = record == null ? AppColors.muted : record.statusColor;
    final statusIcon =
    record == null ? Icons.help_outline : record.statusIcon;
    final statusTitle = record == null ? 'Unreadable' : record.statusTitle;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    scan.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$statusTitle · $_when',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: statusColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right,
                color: AppColors.accentLight, size: 20),
          ],
        ),
      ),
    );
  }
}