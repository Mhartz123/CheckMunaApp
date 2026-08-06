import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'record_detail_screen.dart';
import '../models/scan_record.dart';
import '../services/scan_store.dart';
import '../theme/app_colors.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../screens/report_builder.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => RecordsScreenState();
}

class RecordsScreenState extends State<RecordsScreen> {
  List<Directory> _allDirs = [];
  List<Directory> _filtered = [];
  String _sortBy = 'Name';
  bool _nameAscending = true;
  bool _dateNewest = true;
  String _complianceFilter = '';

  /// Narrows the list to one kind of check; null shows both.
  ScanType? _typeFilter;

  String _searchQuery = '';
  final Set<String> _selected = {};
  bool _isSelecting = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    loadFiles();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> loadFiles() async {
    setState(() => _loading = true);
    try {
      _allDirs = await ScanStore.listRecordDirs();
      _applySort();
    } catch (e) {
      debugPrint('Load files error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applySort() {
    List<Directory> list = List.from(_allDirs);
    if (_searchQuery.isNotEmpty) {
      list = list
          .where((d) => p.basename(d.path)
          .toLowerCase()
          .contains(_searchQuery.toLowerCase()))
          .toList();
    }
    if (_typeFilter != null) {
      list = list.where((d) => ScanStore.load(d)?.type == _typeFilter).toList();
    }
    if (_complianceFilter.isNotEmpty) {
      list = list.where((d) {
        final record = ScanStore.load(d);
        return record?.statusLabel == _complianceFilter;
      }).toList();
    }
    if (_sortBy == 'Name') {
      list.sort((a, b) => _nameAscending
          ? p.basename(a.path).compareTo(p.basename(b.path))
          : p.basename(b.path).compareTo(p.basename(a.path)));
    } else if (_sortBy == 'Date') {
      list.sort((a, b) {
        final aDate = ScanStore.load(a)?.scannedAt ?? a.statSync().modified;
        final bDate = ScanStore.load(b)?.scannedAt ?? b.statSync().modified;
        return _dateNewest ? bDate.compareTo(aDate) : aDate.compareTo(bDate);
      });
    }
    setState(() => _filtered = list);
  }

  void _onSearchChanged(String val) {
    _searchQuery = val;
    _applySort();
  }

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
      _selected.addAll(_filtered.map((d) => d.path));
      _isSelecting = _selected.isNotEmpty;
    });
  }

  // Single delete confirmation
  void _confirmSingleDelete(Directory dir) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFD4A847),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'User Instruction - Delete Record',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Are you sure you want to delete this record?',
                style: TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            const Text(
              '*Note : Deleting this record will permanently remove it (all photos and data) from the app and phone storage.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            const Text('Are you really sure?',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await ScanStore.delete(dir);
                      loadFiles();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE57373),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Delete',
                        style: TextStyle(
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

  // Multi delete confirmation
  void _confirmMultiDelete() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFD4A847),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'User Instruction - Delete Records',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Are you sure you want to delete selected records?',
                style: TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            const Text(
              '*Note : Deleting these records will permanently remove them from the app and phone storage.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            const Text('Are you really sure?',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      for (final path in _selected) {
                        await ScanStore.delete(Directory(path));
                      }
                      _unselectAll();
                      loadFiles();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE57373),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Delete',
                        style: TextStyle(
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

  void _toggleTypeFilter(ScanType type) {
    setState(() {
      _typeFilter = _typeFilter == type ? null : type;
      // "Banned" has no damage-check equivalent and its chip is hidden below,
      // so drop it rather than leave an invisible filter emptying the list.
      if (_typeFilter == ScanType.damage &&
          _complianceFilter == 'WARNING / BANNED') {
        _complianceFilter = '';
      }
    });
    _applySort();
  }

  /// Outcome chips for the current type filter. A damage record's status is
  /// stored on the same COMPLIANT / NON-COMPLIANT scale as a label record's,
  /// but it means something different — so when the list is narrowed to damage
  /// checks the chips are worded for damage and "Banned" (label-only) drops.
  List<Widget> _outcomeChips() {
    final damageOnly = _typeFilter == ScanType.damage;

    void toggle(String value) {
      setState(() =>
          _complianceFilter = _complianceFilter == value ? '' : value);
      _applySort();
    }

    return [
      const Text('Filter :',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      const SizedBox(width: 8),
      _SortChip(
        label: damageOnly ? 'No damage' : 'Compliant',
        selected: _complianceFilter == 'COMPLIANT',
        color: const Color(0xFF4CAF50),
        onTap: () => toggle('COMPLIANT'),
      ),
      const SizedBox(width: 6),
      _SortChip(
        label: damageOnly ? 'Damaged' : 'Non-Compliant',
        selected: _complianceFilter == 'NON-COMPLIANT',
        color: const Color(0xFFFF9800),
        onTap: () => toggle('NON-COMPLIANT'),
      ),
      if (!damageOnly) ...[
        const SizedBox(width: 6),
        _SortChip(
          label: 'Banned',
          selected: _complianceFilter == 'WARNING / BANNED',
          color: const Color(0xFFF44336),
          onTap: () => toggle('WARNING / BANNED'),
        ),
      ],
    ];
  }

  // ── Generate PDF report ───────────────────────────────────────────────────
  Future<void> _generateReport() async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.accentLight),
      ),
    );

    try {
      final pw.Document pdf = await ReportBuilder.build();
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading

      // Open the built-in PDF preview (includes share + print buttons)
      await Printing.layoutPdf(
        onLayout: (_) async => pdf.save(),
        name: 'Label_Check_Compliance_Report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate report: $e'),
          backgroundColor: AppColors.bannedText,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Records',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        elevation: 0,
        centerTitle: true,
        shape: const Border(
          bottom: BorderSide(color: AppColors.border, width: 0.6),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Generate Report',
            onPressed: _generateReport,
          ),
        ],
      ),
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          // Sort bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Sort :',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 8),
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
                    const SizedBox(width: 6),
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
                  ],
                ),
                const SizedBox(height: 6),
                // Report type — the two checks are separate features, so this
                // row comes first and narrows what the status chips below act
                // on.
                Row(
                  children: [
                    const Text('Type :',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 8),
                    _SortChip(
                        label: 'Label',
                        selected: _typeFilter == ScanType.label,
                        color: AppColors.accentLight,
                        onTap: () => _toggleTypeFilter(ScanType.label)),
                    const SizedBox(width: 6),
                    _SortChip(
                        label: 'Damage',
                        selected: _typeFilter == ScanType.damage,
                        color: const Color(0xFF1E88E5),
                        onTap: () => _toggleTypeFilter(ScanType.damage)),
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: _outcomeChips()),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              onChanged: _onSearchChanged,
              style: const TextStyle(fontSize: 13, color: AppColors.text),
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
                  borderSide: const BorderSide(color: AppColors.accentLight, width: 1.5),
                ),
                suffixIcon:
                Icon(Icons.search, color: AppColors.muted),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // Record list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open,
                      size: 64, color: AppColors.muted),
                  const SizedBox(height: 12),
                  Text('No records yet',
                      style: TextStyle(
                          fontSize: 16,
                          color: AppColors.muted)),
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: loadFiles,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                itemCount: _filtered.length,
                itemBuilder: (context, index) {
                  final dir = _filtered[index];
                  final name = p.basename(dir.path);
                  final record = ScanStore.load(dir);
                  final date = record?.scannedAt ?? dir.statSync().modified;
                  final isSelected =
                  _selected.contains(dir.path);

                  return _RecordCard(
                    dir: dir,
                    name: name,
                    date: date,
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

          // Multi-select bottom bar
          if (_isSelecting)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border, width: 0.6)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _selectAll,
                    icon: const Icon(Icons.select_all, color: AppColors.muted),
                    label: const Text('Select All',
                        style: TextStyle(color: AppColors.muted)),
                  ),
                  TextButton.icon(
                    onPressed: _unselectAll,
                    icon: const Icon(Icons.check_box_outline_blank,
                        color: AppColors.muted),
                    label: const Text('Unselect All',
                        style: TextStyle(color: AppColors.muted)),
                  ),
                  ElevatedButton.icon(
                    onPressed: _confirmMultiDelete,
                    icon: const Icon(Icons.close, color: Colors.white),
                    label: const Text('Delete All',
                        style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.bannedText,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Sort chip ────────────────────────────────────────────────────────────────

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppColors.accentLight;
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
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

// ── Report type badge ────────────────────────────────────────────────────────

/// Marks which of the two checks produced a record, so the mixed list stays
/// readable at a glance.
class _TypeBadge extends StatelessWidget {
  final ScanType type;

  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final color = type == ScanType.label
        ? AppColors.accent
        : const Color(0xFF1565C0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        type.shortLabel,
        style: TextStyle(
          fontSize: 9.5,
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ── Record card ──────────────────────────────────────────────────────────────

class _RecordCard extends StatelessWidget {
  final Directory dir;
  final String name;
  final DateTime date;
  final bool isSelected;
  final bool isSelecting;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onSelect;

  const _RecordCard({
    required this.dir,
    required this.name,
    required this.date,
    required this.isSelected,
    required this.isSelecting,
    required this.onTap,
    required this.onDelete,
    required this.onSelect,
  });

  String _formatDate(DateTime dt) =>
      '${dt.year} / ${_pad(dt.month)} / ${_pad(dt.day)}';
  String _pad(int n) => n.toString().padLeft(2, '0');

  /// Icon + colours + pill text for the card, worded for the record's own kind
  /// of check. A damage record stores its outcome on the same status scale as
  /// a label record, but "NON-COMPLIANT" there means "damaged" — so the pill
  /// never shows compliance wording on a damage card.
  ({IconData icon, Color bg, Color fg, String pill}) _visuals(
      ScanRecord? record) {
    if (record == null) {
      return (
        icon: Icons.image_outlined,
        bg: AppColors.surfaceAlt,
        fg: AppColors.muted,
        pill: '—',
      );
    }

    if (record.isDamageCheck) {
      final damage = record.damageCheck;
      if (!damage.available) {
        return (
          icon: Icons.help_outline,
          bg: AppColors.surfaceAlt,
          fg: AppColors.muted,
          pill: 'CHECK UNAVAILABLE',
        );
      }
      return damage.isDamaged
          ? (
              icon: Icons.warning_amber_rounded,
              bg: AppColors.bannedBg,
              fg: AppColors.bannedText,
              pill: 'DAMAGED',
            )
          : (
              icon: Icons.check,
              bg: AppColors.compliantBg,
              fg: AppColors.compliantText,
              pill: 'NO DAMAGE',
            );
    }

    switch (record.status) {
      case ComplianceStatus.compliant:
        return (
          icon: Icons.check,
          bg: AppColors.compliantBg,
          fg: AppColors.compliantText,
          pill: 'COMPLIANT',
        );
      case ComplianceStatus.nonCompliant:
        return (
          icon: Icons.warning_amber_rounded,
          bg: AppColors.nonCompliantBg,
          fg: AppColors.nonCompliantText,
          pill: 'NON-COMPLIANT',
        );
      case ComplianceStatus.banned:
        return (
          icon: Icons.block,
          bg: AppColors.bannedBg,
          fg: AppColors.bannedText,
          pill: 'WARNING / BANNED',
        );
    }
  }

  /// The at-a-glance fields for this record's kind of check.
  ///
  ///  • Label — product name, expiration date, all-labels-present yes/no.
  ///  • Damage — what damage was found and on which sides.
  List<Widget> _summaryLines(ScanRecord record) {
    if (record.isLabelCheck) {
      return [
        _line('Product', record.productName),
        _line('Expiration', record.expiration),
        _line('All labels present', record.allLabelsPresent ? 'Yes' : 'No'),
      ];
    }

    final damage = record.damageCheck;
    if (!damage.available) {
      return [_line('Damage', 'Could not be checked')];
    }
    if (!damage.isDamaged) {
      return [_line('Damage', 'None detected')];
    }
    return [
      _line('Damage', damage.damageTypes.join(', ')),
      _line('Found on', damage.affectedSides),
    ];
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final record = ScanStore.load(dir);
    final visuals = _visuals(record);

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
              // Status icon circle — leading visual indicator
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

              // Main content column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name row + delete + checkbox (name is NOT editable —
                    // renaming after save is intentionally unsupported to
                    // prevent tampering with data already reported upstream)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Delete button
                        Semantics(
                          button: true,
                          label: 'Delete record',
                          child: GestureDetector(
                            onTap: onDelete,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColors.bannedBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(Icons.close,
                                  color: AppColors.bannedText, size: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Multi-select checkbox
                        Semantics(
                          button: true,
                          checked: isSelected,
                          label: 'Select record',
                          child: GestureDetector(
                            onTap: onSelect,
                            child: Container(
                              width: 20,
                              height: 20,
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
                                      size: 12, color: Colors.white)
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),

                    // Date
                    Text(
                      _formatDate(date),
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.muted),
                    ),
                    const SizedBox(height: 8),

                    // Which check this is, then its outcome.
                    Row(
                      children: [
                        if (record != null) ...[
                          _TypeBadge(type: record.type),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: visuals.bg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              visuals.pill,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: visuals.fg,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Only the fields that belong to this kind of report.
                    if (record != null) ...[
                      const SizedBox(height: 6),
                      ..._summaryLines(record),
                    ],
                  ],
                ),
              ),

              // Trailing chevron to signal tappability
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
