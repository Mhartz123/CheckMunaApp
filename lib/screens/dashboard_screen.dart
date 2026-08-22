import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/scan_record.dart';
import '../services/scan_store.dart';
import '../theme/app_colors.dart';
import '../widgets/capture_tips.dart';
import '../widgets/theme_toggle_button.dart';
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
///
/// The header also carries the light/dark toggle. This screen stays mounted
/// permanently as one of AppShell's two tabs, so it (and Records, its sibling
/// tab) are the only screens where a `const` custom widget whose `build()`
/// reads `AppColors` could go visually stale after a toggle — Flutter skips
/// rebuilding a child when it sees the exact same canonicalized const widget
/// instance again. Every other screen is reached via `Navigator.push`, so it
/// is always freshly built after the current theme is already set, and that
/// specific risk doesn't apply there.
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

  // Totals across ALL saved records, for the summary card. Computed in the
  // same pass that picks the recent few, so there's no second directory walk.
  int _totalScans = 0;
  int _compliantCount = 0;
  int _flaggedCount = 0; // non-compliant + banned

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

      // Tally every readable record for the summary card.
      var total = 0, compliant = 0, flagged = 0;
      for (final s in scans) {
        final r = s.record;
        if (r == null) continue; // unreadable: counts toward nothing
        total++;
        switch (r.status) {
          case ComplianceStatus.compliant:
            compliant++;
            break;
          case ComplianceStatus.nonCompliant:
          case ComplianceStatus.banned:
            flagged++;
            break;
        }
      }

      if (!mounted) return;
      setState(() {
        _recent = scans.take(_maxRecent).toList();
        _totalScans = total;
        _compliantCount = compliant;
        _flaggedCount = flagged;
        _loadingRecent = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recent = [];
        _totalScans = 0;
        _compliantCount = 0;
        _flaggedCount = 0;
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
              height: 56, // matches Records' AppBar toolbarHeight exactly
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
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
                  // Was `const Expanded(...)` — dropped since AppColors.text
                  // now varies with the theme toggle.
                  Expanded(
                    child: Text(
                      'CheckMuna',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  // Light/dark toggle — now shared with the packaging
                  // picker and Records via widgets/theme_toggle_button.dart
                  // so all three stay in sync.
                  ThemeToggleButton(compact: true),
                  const SizedBox(width: 4),
                  // Photo tips moved here from the old always-visible
                  // banner, so the guidance is one tap away instead of
                  // permanently occupying the top of the screen.
                  IconButton(
                    onPressed: () => showCaptureTips(context),
                    icon: const Icon(Icons.help_outline),
                    color: AppColors.muted,
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 36, minHeight: 36),
                    tooltip: 'Photo tips',
                  ),
                ],
              ),
            ),

            // ── Scan options — each card sizes to its own content ──────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  children: [
                    // Summary card — today's tallies across all records.
                    _SummaryCard(
                      scans: _totalScans,
                      compliant: _compliantCount,
                      flagged: _flaggedCount,
                      loading: _loadingRecent,
                    ),
                    const SizedBox(height: 16),
                    _DashboardCard(
                      icon: Icons.list_alt_outlined,
                      iconColor: AppColors.labelKind,
                      title: 'Check Labels',
                      subtitle: 'Verify against FDA registry',
                      onTap: () => _openLabelCamera(context),
                    ),
                    const SizedBox(height: 10),
                    _DashboardCard(
                      icon: Icons.inventory_2_outlined,
                      iconColor: AppColors.damageKind,
                      title: 'Damage Detection',
                      subtitle: 'Check packaging integrity',
                      onTap: () =>
                          _openPackagingPicker(context, CameraMode.damage),
                    ),
                    const SizedBox(height: 10),
                    _DashboardCard(
                      icon: Icons.manage_search,
                      iconColor: AppColors.inspection,
                      title: 'Inspection Mode',
                      subtitle: 'Combined label + damage result',
                      onTap: () => _openPackagingPicker(
                          context, CameraMode.inspection),
                    ),
                    const SizedBox(height: 20),
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

/// The green summary card at the top of Home: today's tallies (Scans /
/// Compliant / Flagged) across all saved records. Uses the accent gradient
/// so it reads as the primary status surface, matching the mockup.
class _SummaryCard extends StatelessWidget {
  final int scans;
  final int compliant;
  final int flagged;
  final bool loading;

  const _SummaryCard({
    required this.scans,
    required this.compliant,
    required this.flagged,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accent, AppColors.accentLight],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'TODAY',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat(loading ? '—' : '$scans', 'Scans'),
              _divider(),
              _stat(loading ? '—' : '$compliant', 'Compliant'),
              _divider(),
              _stat(loading ? '—' : '$flagged', 'Flagged'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: Colors.white.withValues(alpha: 0.25),
    );
  }
}

/// Compact action row — small icon tile, title + one-line subtitle, chevron.
/// Replaces the earlier tall card with a paragraph description; the Clean
/// Clinical direction reads as precise rather than bloated, and the shorter
/// rows leave room for the summary card above.
class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.muted,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  color: AppColors.accentLight, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// The recent-scans strip: a section header plus up to three saved records,
/// newest first. Kept visually lighter than the scan cards above it — this
/// is a shortcut into Records, not a fourth action.
///
/// With no records saved it shows an empty state rather than collapsing, so
/// a first-run screen explains the blank space instead of just having it.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Was `const Padding(...)` — dropped since AppColors.muted now
        // varies with the theme toggle.
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
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
        else if (scans.isEmpty)
        // Was `const _NoScansYet()`. This one matters at runtime, not
        // just for compilation: DashboardScreen stays permanently mounted
        // (it's an AppShell tab), so on a theme toggle this widget would
        // be asked to rebuild — but if it's still the exact same const
        // instance as before, Flutter treats that as "nothing changed"
        // and skips calling its build() again, leaving it showing the
        // old theme's colors. Dropping const makes a fresh instance each
        // rebuild, so it always re-reads AppColors.
          _NoScansYet()
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
                  // Was `const Divider(...)` — dropped since
                  // AppColors.border now varies with the theme toggle.
                    Divider(
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
                    // Was `const TextStyle` — dropped since AppColors.text
                    // now varies with the theme toggle.
                    style: TextStyle(
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
            // Was `const Icon(...)` — dropped since AppColors.accentLight
            // now varies with the theme toggle.
            Icon(Icons.chevron_right,
                color: AppColors.accentLight, size: 20),
          ],
        ),
      ),
    );
  }
}

/// First-run state for the recent-scans strip. Deliberately says what to do
/// rather than only that there is nothing here — the space below the scan
/// cards is otherwise blank with no explanation.
class _NoScansYet extends StatelessWidget {
  const _NoScansYet();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.document_scanner_outlined,
              color: AppColors.accentLight, size: 28),
          const SizedBox(height: 10),
          // Was `const Text(...)` — dropped since AppColors.text now varies
          // with the theme toggle.
          Text(
            'No scans yet',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pick one of the checks above to scan your first product. '
                'Your results will show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.muted,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}