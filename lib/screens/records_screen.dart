import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'record_detail_screen.dart';
import '../services/scan_store.dart';
import '../models/scan_record.dart';
import '../theme/app_colors.dart';
import '../widgets/theme_toggle_button.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/report_builder.dart';

/// One saved record, parsed once per load.
///
/// The list used to call [ScanStore.load] from the filter, from every sort
/// comparison and again from every card's build — fine for twenty records,
/// seconds of disk reads for a thousand. Now each data.json is read exactly
/// once in [RecordsScreenState.loadFiles] and everything else works on this.
class _Entry {
  final Directory dir;
  final String name;

  /// Null when data.json is missing or unreadable. Such a record still lists
  /// under the "All" type so it can be found and deleted.
  final ScanRecord? record;
  final DateTime date;

  const _Entry({
    required this.dir,
    required this.name,
    required this.record,
    required this.date,
  });
}

enum _DatePreset { any, today, last7, last30, thisYear, lastYear, custom }

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => RecordsScreenState();
}

class RecordsScreenState extends State<RecordsScreen> {
  /// Records shown per page. Long histories are paged rather than one endless
  /// scroll, so record 900 is a few taps away instead of a long fling.
  static const int _pageSize = 20;

  List<_Entry> _all = [];
  List<_Entry> _filtered = [];
  int _page = 0;
  final ScrollController _scroll = ScrollController();

  String _sortBy = 'Date';
  bool _nameAscending = true;
  bool _dateNewest = true;
  String _complianceFilter = '';
  String _searchQuery = '';
  final Set<String> _selected = {};
  bool _isSelecting = false;
  bool _loading = true;

  /// Null means every scan type.
  ScanKind? _kindFilter;

  _DatePreset _datePreset = _DatePreset.any;

  /// Inclusive start / exclusive end of the date filter, or null for "any".
  DateTime? _dateStart;
  DateTime? _dateEnd;

  @override
  void initState() {
    super.initState();
    loadFiles();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> loadFiles() async {
    setState(() => _loading = true);
    try {
      final dirs = await ScanStore.listRecordDirs();
      _all = dirs.map((dir) {
        final record = ScanStore.load(dir);
        return _Entry(
          dir: dir,
          name: p.basename(dir.path),
          record: record,
          date: record?.scannedAt ?? dir.statSync().modified,
        );
      }).toList();
      // Keep the current page on a reload (e.g. after a delete) when it
      // still exists; _applySort clamps it otherwise.
      _applySort(resetPage: false);
    } catch (e) {
      debugPrint('Load files error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Filters ──────────────────────────────────────────────────────────────

  static String _kindName(ScanKind? kind) {
    switch (kind) {
      case null:
        return 'All';
      case ScanKind.label:
        return 'Label';
      case ScanKind.damage:
        return 'Damage';
      case ScanKind.both:
        return 'Inspect';
    }
  }

  static Color _kindColor(ScanKind? kind) {
    switch (kind) {
      case null:
        return AppColors.accentLight;
      case ScanKind.label:
        return AppColors.labelKind;
      case ScanKind.damage:
        return AppColors.damageKind;
      case ScanKind.both:
        return AppColors.inspection;
    }
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _dateLabel {
    switch (_datePreset) {
      case _DatePreset.any:
        return 'Any date';
      case _DatePreset.today:
        return 'Today';
      case _DatePreset.last7:
        return 'Last 7 days';
      case _DatePreset.last30:
        return 'Last 30 days';
      case _DatePreset.thisYear:
      case _DatePreset.lastYear:
        return '${_dateStart!.year}';
      case _DatePreset.custom:
        final last = _dateEnd!.subtract(const Duration(days: 1));
        return _fmtDate(_dateStart!) == _fmtDate(last)
            ? _fmtDate(_dateStart!)
            : '${_fmtDate(_dateStart!)} – ${_fmtDate(last)}';
    }
  }

  bool get _hasActiveFilters =>
      _kindFilter != null ||
      _complianceFilter.isNotEmpty ||
      _datePreset != _DatePreset.any ||
      _searchQuery.isNotEmpty;

  /// Human-readable description of the active filters, printed on the PDF so
  /// a reader knows exactly which subset of records it covers.
  String get _filterSummary {
    final parts = <String>[
      if (_kindFilter != null) 'Type: ${_kindName(_kindFilter)}',
      if (_complianceFilter.isNotEmpty)
        'Status: ${ScanRecord.isWarningLabel(_complianceFilter) ? 'Warning' : _complianceFilter == 'COMPLIANT' ? 'Compliant' : 'Non-Compliant'}',
      if (_datePreset != _DatePreset.any) 'Date: $_dateLabel',
      if (_searchQuery.isNotEmpty) 'Name contains "$_searchQuery"',
    ];
    return parts.join(' · ');
  }

  void _setDatePreset(_DatePreset preset, {DateTimeRange? custom}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    DateTime? start;
    DateTime? end;
    switch (preset) {
      case _DatePreset.any:
        break;
      case _DatePreset.today:
        start = today;
        end = tomorrow;
        break;
      case _DatePreset.last7:
        start = today.subtract(const Duration(days: 6));
        end = tomorrow;
        break;
      case _DatePreset.last30:
        start = today.subtract(const Duration(days: 29));
        end = tomorrow;
        break;
      case _DatePreset.thisYear:
        start = DateTime(now.year);
        end = DateTime(now.year + 1);
        break;
      case _DatePreset.lastYear:
        start = DateTime(now.year - 1);
        end = DateTime(now.year);
        break;
      case _DatePreset.custom:
        start = DateTime(
            custom!.start.year, custom.start.month, custom.start.day);
        end = DateTime(custom.end.year, custom.end.month, custom.end.day)
            .add(const Duration(days: 1));
        break;
    }
    setState(() {
      _datePreset = preset;
      _dateStart = start;
      _dateEnd = end;
    });
    _applySort();
  }

  Future<void> _pickDateFilter() async {
    final now = DateTime.now();
    final choice = await showModalBottomSheet<_DatePreset>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        Widget option(_DatePreset preset, String label, IconData icon) {
          final selected = preset == _datePreset;
          return ListTile(
            leading: Icon(icon,
                color: selected ? AppColors.accent : AppColors.muted),
            title: Text(label,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.text,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                )),
            trailing: selected
                ? Icon(Icons.check, color: AppColors.accent, size: 20)
                : null,
            onTap: () => Navigator.of(context).pop(preset),
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Text('Filter by scan date',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      )),
                ),
                option(_DatePreset.any, 'Any date', Icons.all_inclusive),
                option(_DatePreset.today, 'Today', Icons.today_outlined),
                option(_DatePreset.last7, 'Last 7 days', Icons.date_range),
                option(_DatePreset.last30, 'Last 30 days', Icons.date_range),
                option(_DatePreset.thisYear, 'This year (${now.year})',
                    Icons.calendar_today_outlined),
                option(_DatePreset.lastYear, 'Last year (${now.year - 1})',
                    Icons.history),
                option(_DatePreset.custom, 'Custom range…',
                    Icons.edit_calendar_outlined),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    if (choice != _DatePreset.custom) {
      _setDatePreset(choice);
      return;
    }

    final earliest = _all.isEmpty
        ? DateTime(now.year - 1)
        : _all.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);
    final first = DateTime(math.min(earliest.year, now.year - 1));
    final range = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: now,
      initialDateRange: _datePreset == _DatePreset.custom
          ? DateTimeRange(
              start: _dateStart!,
              end: _dateEnd!.subtract(const Duration(days: 1)))
          : null,
      helpText: 'Show scans between',
    );
    if (range == null || !mounted) return;
    _setDatePreset(_DatePreset.custom, custom: range);
  }

  void _clearFilters() {
    setState(() {
      _kindFilter = null;
      _complianceFilter = '';
      _datePreset = _DatePreset.any;
      _dateStart = null;
      _dateEnd = null;
      _searchQuery = '';
      _searchController.clear();
    });
    _applySort();
  }

  final TextEditingController _searchController = TextEditingController();

  void _applySort({bool resetPage = true}) {
    final query = _searchQuery.toLowerCase();
    final list = _all.where((e) {
      if (query.isNotEmpty && !e.name.toLowerCase().contains(query)) {
        return false;
      }
      if (_kindFilter != null && e.record?.kind != _kindFilter) return false;
      if (_complianceFilter.isNotEmpty &&
          e.record?.statusLabel != _complianceFilter) {
        return false;
      }
      if (_dateStart != null && e.date.isBefore(_dateStart!)) return false;
      if (_dateEnd != null && !e.date.isBefore(_dateEnd!)) return false;
      return true;
    }).toList();

    if (_sortBy == 'Name') {
      list.sort((a, b) => _nameAscending
          ? a.name.compareTo(b.name)
          : b.name.compareTo(a.name));
    } else {
      list.sort((a, b) =>
          _dateNewest ? b.date.compareTo(a.date) : a.date.compareTo(b.date));
    }

    setState(() {
      _filtered = list;
      final lastPage = math.max(0, (list.length - 1) ~/ _pageSize);
      _page = resetPage ? 0 : math.min(_page, lastPage);
      // Drop selections that are no longer visible under the new filters,
      // so Delete never acts on records the user can't see.
      final visible = list.map((e) => e.dir.path).toSet();
      _selected.removeWhere((path) => !visible.contains(path));
      _isSelecting = _selected.isNotEmpty;
    });
    if (resetPage && _scroll.hasClients) _scroll.jumpTo(0);
  }

  void _onSearchChanged(String val) {
    _searchQuery = val.trim();
    _applySort();
  }

  // ── Pagination ───────────────────────────────────────────────────────────

  int get _pageCount =>
      _filtered.isEmpty ? 1 : ((_filtered.length - 1) ~/ _pageSize) + 1;

  List<_Entry> get _pageEntries {
    final start = _page * _pageSize;
    if (start >= _filtered.length) return const [];
    return _filtered.sublist(
        start, math.min(start + _pageSize, _filtered.length));
  }

  void _goToPage(int page) {
    final target = page.clamp(0, _pageCount - 1);
    if (target == _page) return;
    setState(() => _page = target);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  // ── Selection / delete ───────────────────────────────────────────────────

  void _toggleSelect(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
      _isSelecting = _selected.isNotEmpty;
    });
  }

  void _unselectAll() {
    setState(() {
      _selected.clear();
      _isSelecting = false;
    });
  }

  void _selectAll() {
    setState(() {
      _selected.addAll(_filtered.map((e) => e.dir.path));
      _isSelecting = _selected.isNotEmpty;
    });
  }

  void _confirmSingleDelete(Directory dir) {
    _showDeleteSheet(
      title: 'Delete record',
      subtitle: 'Are you sure you want to delete this record?',
      note: 'This permanently removes the record — all its photos and data '
          '— from the app and from phone storage. It cannot be undone.',
      confirmLabel: 'Delete',
      onConfirm: () async {
        await ScanStore.delete(dir);
        loadFiles();
      },
    );
  }

  void _confirmMultiDelete() {
    final count = _selected.length;
    _showDeleteSheet(
      title: 'Delete $count record${count == 1 ? '' : 's'}',
      subtitle: 'Are you sure you want to delete the selected '
          'record${count == 1 ? '' : 's'}?',
      note: 'This permanently removes them — all their photos and data — '
          'from the app and from phone storage. It cannot be undone.',
      confirmLabel: 'Delete all',
      onConfirm: () async {
        for (final path in _selected) {
          await ScanStore.delete(Directory(path));
        }
        _unselectAll();
        loadFiles();
      },
    );
  }

  void _showDeleteSheet({
    required String title,
    required String subtitle,
    required String note,
    required String confirmLabel,
    required Future<void> Function() onConfirm,
  }) {
    showModalBottomSheet(
      context: context,

      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.delete_outline,
                      color: AppColors.warningText, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.text,
                          )),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.muted,
                          )),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: AppColors.warningText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      note,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.warningText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.text,
                      backgroundColor: AppColors.surface,
                      side: BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await onConfirm();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC62828),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: Text(confirmLabel,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Exports exactly what the list shows: the records under the active
  /// filters and search, in the on-screen order. The PDF's metrics, tables
  /// and photos are all built from this one list, and its header states the
  /// filter so a reader knows it is a subset.
  Future<void> _generateReport() async {
    final entries = List<_Entry>.of(_filtered);
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No records match the current filters to export.')),
      );
      return;
    }

    final summary = _filterSummary;
    final count = entries.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export PDF report'),
        content: Text(
          '$count record${count == 1 ? '' : 's'} will be included'
          '${summary.isEmpty ? ' (all records).' : ', matching:\n$summary'}'
          '\n\nOnly these records, their photos and their totals appear in '
          'the report.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Export'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(color: AppColors.accentLight),
      ),
    );

    try {
      final pw.Document pdf = await ReportBuilder.buildFromDirs(
        entries.map((e) => e.dir).toList(),
        filterSummary: summary,
        periodStart: _dateStart,
        periodEnd: _dateEnd?.subtract(const Duration(days: 1)),
      );
      if (!mounted) return;
      Navigator.of(context).pop();

      await Printing.layoutPdf(
        onLayout: (_) async => pdf.save(),
        name: 'CheckMuna_Compliance_Report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate report: $e'),
          backgroundColor: AppColors.warningText,
        ),
      );
    }
  }

  Widget _rowLabel(String text) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: SizedBox(
          width: 48,
          child: Text(text,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text)),
        ),
      );

  Widget _statusChip(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: _SortChip(
          label: label,
          selected: _complianceFilter == value,
          color: color,
          onTap: () {
            setState(() =>
                _complianceFilter = _complianceFilter == value ? '' : value);
            _applySort();
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pageEntries = _pageEntries;
    final firstShown = _page * _pageSize + 1;
    final lastShown = _page * _pageSize + pageEntries.length;

    return Scaffold(
      appBar: AppBar(

        titleSpacing: 16,
        title: Text('Records',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.text)),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        elevation: 0,
        centerTitle: false,

        toolbarHeight: 56,

        shape: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.6),
        ),
        actions: [

          ThemeToggleButton(),

          Padding(
            padding: const EdgeInsets.only(right: 10, top: 8, bottom: 8),
            child: Tooltip(
              message: 'Export the records shown to PDF',
              child: Material(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: _generateReport,
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(
                    padding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.picture_as_pdf_outlined,
                            color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text('PDF',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            )),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.bg,
      body: Column(
        children: [

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _rowLabel('Sort'),
                      _SortChip(
                          label: _sortBy == 'Date'
                              ? (_dateNewest ? 'Date Latest' : 'Date Oldest')
                              : 'Date Latest',
                          selected: _sortBy == 'Date',
                          onTap: () {
                            if (_sortBy == 'Date') {
                              setState(() => _dateNewest = !_dateNewest);
                            } else {
                              setState(() { _sortBy = 'Date'; _dateNewest = true; });
                            }
                            _applySort();
                          }),
                      const SizedBox(width: 6),
                      _SortChip(
                          label: _sortBy == 'Name'
                              ? (_nameAscending ? 'Name A→Z' : 'Name Z→A')
                              : 'Name A→Z',
                          selected: _sortBy == 'Name',
                          onTap: () {
                            if (_sortBy == 'Name') {
                              setState(() => _nameAscending = !_nameAscending);
                            } else {
                              setState(() { _sortBy = 'Name'; _nameAscending = true; });
                            }
                            _applySort();
                          }),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _rowLabel('Type'),
                      for (final kind in <ScanKind?>[
                        null,
                        ScanKind.label,
                        ScanKind.damage,
                        ScanKind.both,
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _SortChip(
                            label: _kindName(kind),
                            selected: _kindFilter == kind,
                            color: _kindColor(kind),
                            onTap: () {
                              setState(() => _kindFilter = kind);
                              _applySort();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _rowLabel('Filter'),
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _SortChip(
                          label: _dateLabel,
                          icon: Icons.calendar_month_outlined,
                          trailingIcon: Icons.arrow_drop_down,
                          selected: _datePreset != _DatePreset.any,
                          onTap: _pickDateFilter,
                        ),
                      ),
                      _statusChip('Compliant', 'COMPLIANT',
                          const Color(0xFF4CAF50)),
                      _statusChip('Non-Compliant', 'NON-COMPLIANT',
                          const Color(0xFFFF9800)),
                      _statusChip('Warned', ScanRecord.warningLabel,
                          const Color(0xFFF44336)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,

              style: TextStyle(fontSize: 13, color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Search by name',
                hintStyle: TextStyle(color: AppColors.muted, fontSize: 13),
                isDense: true,
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),

                  borderSide: BorderSide(color: AppColors.accentLight, width: 1.5),
                ),
                suffixIcon:
                Icon(Icons.search, color: AppColors.muted),
              ),
            ),
          ),

          if (!_loading && _all.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _hasActiveFilters
                          ? '${_filtered.length} of ${_all.length} records match'
                          : '${_all.length} record${_all.length == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ),
                  if (_hasActiveFilters)
                    TextButton(
                      onPressed: _clearFilters,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text('Clear filters',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.accent)),
                    ),
                ],
              ),
            ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                      _all.isEmpty ? Icons.folder_open : Icons.filter_alt_off,
                      size: 64,
                      color: AppColors.muted),
                  const SizedBox(height: 12),
                  Text(
                      _all.isEmpty
                          ? 'No records yet'
                          : 'No records match these filters',
                      style: TextStyle(
                          fontSize: 16,
                          color: AppColors.muted)),
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: loadFiles,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                itemCount: pageEntries.length,
                itemBuilder: (context, index) {
                  final entry = pageEntries[index];
                  final dir = entry.dir;
                  final isSelected =
                  _selected.contains(dir.path);

                  return _RecordCard(
                    dir: dir,
                    name: entry.name,
                    date: entry.date,
                    record: entry.record,
                    isSelected: isSelected,
                    isSelecting: _isSelecting,
                    onTap: () {
                      if (_isSelecting) {
                        _toggleSelect(dir.path);
                      } else {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RecordDetailScreen(
                                recordDir: dir),
                          ),
                        );
                      }
                    },
                    onDelete: () => _confirmSingleDelete(dir),
                    onSelect: () => _toggleSelect(dir.path),
                  );
                },
              ),
            ),
          ),

          if (!_loading && _filtered.length > _pageSize)
            _PaginationBar(
              page: _page,
              pageCount: _pageCount,
              firstShown: firstShown,
              lastShown: lastShown,
              total: _filtered.length,
              onPage: _goToPage,
            ),

          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_isSelecting
                ? const SizedBox(width: double.infinity)
                : AnimatedSlide(
              offset: _isSelecting ? Offset.zero : const Offset(0, 1),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _isSelecting ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border(
                        top: BorderSide(
                            color: AppColors.border, width: 0.6)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: _selectAll,

                        icon: Icon(Icons.select_all, color: AppColors.muted),

                        label: Text('Select All',
                            style: TextStyle(color: AppColors.muted)),
                      ),
                      TextButton.icon(
                        onPressed: _unselectAll,

                        icon: Icon(Icons.check_box_outline_blank,
                            color: AppColors.muted),

                        label: Text('Unselect All',
                            style: TextStyle(color: AppColors.muted)),
                      ),
                      ElevatedButton.icon(
                        onPressed: _confirmMultiDelete,
                        icon: const Icon(Icons.close, color: Colors.white),
                        label: Text('Delete (${_selected.length})',
                            style: const TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warningText,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Page controls under the records list: first / previous / "21–40 of
/// 1,012 · Page 2 of 51" / next / last.
class _PaginationBar extends StatelessWidget {
  final int page;
  final int pageCount;
  final int firstShown;
  final int lastShown;
  final int total;
  final ValueChanged<int> onPage;

  const _PaginationBar({
    required this.page,
    required this.pageCount,
    required this.firstShown,
    required this.lastShown,
    required this.total,
    required this.onPage,
  });

  @override
  Widget build(BuildContext context) {
    final atStart = page == 0;
    final atEnd = page >= pageCount - 1;

    Widget button(IconData icon, String tooltip, bool enabled, int target) =>
        IconButton(
          onPressed: enabled ? () => onPage(target) : null,
          icon: Icon(icon),
          tooltip: tooltip,
          color: AppColors.accent,
          disabledColor: AppColors.border,
          visualDensity: VisualDensity.compact,
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.6)),
      ),
      child: Row(
        children: [
          button(Icons.first_page, 'First page', !atStart, 0),
          button(Icons.chevron_left, 'Previous page', !atStart, page - 1),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Page ${page + 1} of $pageCount',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text)),
                Text('$firstShown–$lastShown of $total',
                    style: TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ),
          ),
          button(Icons.chevron_right, 'Next page', !atEnd, page + 1),
          button(Icons.last_page, 'Last page', !atEnd, pageCount - 1),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final IconData? icon;
  final IconData? trailingIcon;

  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.icon,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppColors.accentLight;
    final fg = selected ? Colors.white : AppColors.muted;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? activeColor : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? activeColor : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            if (trailingIcon != null) Icon(trailingIcon, size: 16, color: fg),
          ],
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  final Directory dir;
  final String name;
  final DateTime date;
  final ScanRecord? record;
  final bool isSelected;
  final bool isSelecting;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onSelect;

  const _RecordCard({
    required this.dir,
    required this.name,
    required this.date,
    required this.record,
    required this.isSelected,
    required this.isSelecting,
    required this.onTap,
    required this.onDelete,
    required this.onSelect,
  });

  String _formatDate(DateTime dt) =>
      '${dt.year} / ${_pad(dt.month)} / ${_pad(dt.day)}';
  String _pad(int n) => n.toString().padLeft(2, '0');

  ({IconData icon, Color bg, Color fg, Color pillBg, Color pillText}) _statusVisuals(
      String status) {
    // Checked before the switch: records saved before the Banned→Warning
    // rename still carry the old status string, and they should draw
    // identically to new ones rather than falling through to the default.
    if (ScanRecord.isWarningLabel(status)) {
      return (
      icon: Icons.report_problem_outlined,
      bg: AppColors.warningBg,
      fg: AppColors.warningText,
      pillBg: AppColors.warningBg,
      pillText: AppColors.warningText,
      );
    }
    switch (status) {
      case 'COMPLIANT':
        return (
        icon: Icons.check,
        bg: AppColors.compliantBg,
        fg: AppColors.compliantText,
        pillBg: AppColors.compliantBg,
        pillText: AppColors.compliantText,
        );
      case 'NON-COMPLIANT':
        return (
        icon: Icons.warning_amber_rounded,
        bg: AppColors.nonCompliantBg,
        fg: AppColors.nonCompliantText,
        pillBg: AppColors.nonCompliantBg,
        pillText: AppColors.nonCompliantText,
        );
      default:
        return (
        icon: Icons.image_outlined,
        bg: AppColors.surfaceAlt,
        fg: AppColors.muted,
        pillBg: AppColors.surfaceAlt,
        pillText: AppColors.muted,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Two strings, deliberately: [ScanRecord.statusLabel] is the persisted
    // one the colours and filters key off — including the legacy spellings a
    // pre-rename record still carries — and [ScanRecord.statusBadge] is what
    // the user is allowed to read.
    final status = record?.statusLabel ?? '—';
    final badge = record?.statusBadge ?? '—';
    final keyword = record?.matchedKeyword ?? '—';
    final packagingType = record?.packagingType;
    final visuals = _statusVisuals(status);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onSelect,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.accentLight : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Container(
                width: 44,
                height: 44,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: visuals.bg,
                  shape: BoxShape.circle,
                ),
                child: Icon(visuals.icon, color: visuals.fg, size: 21),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,

                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),

                        GestureDetector(
                          onTap: onDelete,
                          child: Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.warningBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.close,
                                color: AppColors.warningText, size: 16),
                          ),
                        ),

                        const SizedBox(width: 10),

                        GestureDetector(
                          onTap: onSelect,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: AppColors.border, width: 1.5),
                              color: isSelected
                                  ? AppColors.accentLight
                                  : AppColors.surface,
                            ),
                            child: isSelected
                                ? const Icon(Icons.check,
                                size: 15, color: Colors.white)
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),

                    Text(
                      _formatDate(date),

                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.muted),
                    ),
                    const SizedBox(height: 8),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: visuals.pillBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: visuals.pillText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (packagingType != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              packagingType.label,

                              style: TextStyle(
                                fontSize: 10.5,
                                color: AppColors.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (keyword != '—') ...[
                      const SizedBox(height: 5),
                      Text(
                        'Detection basis: $keyword',

                        style: TextStyle(
                            fontSize: 11.5, color: AppColors.muted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Icon(Icons.chevron_right,
                    size: 18, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
