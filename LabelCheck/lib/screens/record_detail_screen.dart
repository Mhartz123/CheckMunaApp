import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../models/scan_record.dart';
import '../services/scan_store.dart';
import '../theme/app_colors.dart';
import '../widgets/damage_findings.dart';

/// Full report for one saved record. Label checks and damage checks report
/// different things, so the body below branches on [ScanRecord.type].
class RecordDetailScreen extends StatefulWidget {
  final Directory recordDir;
  const RecordDetailScreen({super.key, required this.recordDir});

  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen> {
  ScanRecord? _record;
  List<File> _photos = [];

  /// Damage records only — lets each box photo be captioned with its side.
  Map<BoxSlot, File> _boxPhotos = {};
  int _mainPhotoIndex = 0;

  String _formatDate(DateTime dt) =>
      '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}  ${_pad(dt.hour)}:${_pad(dt.minute)}';
  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  void initState() {
    super.initState();
    _record = ScanStore.load(widget.recordDir);
    _photos = ScanStore.photosInOrder(widget.recordDir);
    _boxPhotos = ScanStore.boxPhotosBySlot(widget.recordDir);
  }

  void _openFullscreen(int index) {
    if (_photos.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullscreenPhotoViewer(
          photos: _photos,
          initialIndex: index,
        ),
      ),
    );
  }

  /// Caption for the thumbnail at [index] — damage records name the box side.
  String? _captionFor(int index) {
    final record = _record;
    if (record == null || !record.isDamageCheck) return null;
    if (index >= _boxPhotos.length) return null;
    return _boxPhotos.keys.elementAt(index).sideName;
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;
    final isDamage = record?.isDamageCheck ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(
            isDamage ? 'Physical Damage Check' : 'Label Check',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        centerTitle: true,
      ),
      backgroundColor: Colors.white,
      body: record == null
          ? const Center(child: Text('Record data not found.'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _photoGallery(),
                  const SizedBox(height: 16),
                  if (record.isLabelCheck)
                    ..._labelSections(record)
                  else
                    ..._damageSections(record),
                ],
              ),
            ),
    );
  }

  // ── Shared photo gallery ───────────────────────────────────────────────────

  Widget _photoGallery() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: 'Product photo, tap to view fullscreen',
          child: GestureDetector(
            onTap: () => _openFullscreen(_mainPhotoIndex),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _photos.isEmpty
                  ? Container(
                      width: double.infinity,
                      height: 240,
                      color: Colors.grey.shade200,
                      child: Icon(Icons.image_not_supported_outlined,
                          color: Colors.grey.shade400, size: 48),
                    )
                  : Image.file(_photos[_mainPhotoIndex],
                      width: double.infinity, height: 240, fit: BoxFit.cover),
            ),
          ),
        ),
        if (_captionFor(_mainPhotoIndex) != null) ...[
          const SizedBox(height: 6),
          Text('Showing: ${_captionFor(_mainPhotoIndex)}',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
        if (_photos.length > 1) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => Column(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _mainPhotoIndex = i),
                    onDoubleTap: () => _openFullscreen(i),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: i == _mainPhotoIndex
                              ? AppColors.accentLight
                              : AppColors.border,
                          width: i == _mainPhotoIndex ? 2 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.file(_photos[i],
                            width: 64, height: 64, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  if (_captionFor(i) != null) ...[
                    const SizedBox(height: 3),
                    Text(_captionFor(i)!,
                        style:
                            TextStyle(fontSize: 10, color: AppColors.muted)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Label check report ─────────────────────────────────────────────────────

  List<Widget> _labelSections(ScanRecord record) {
    final name = p.basename(widget.recordDir.path);

    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.statusTitle,
                    style: TextStyle(
                        color: record.statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                      color: record.statusColor,
                      borderRadius: BorderRadius.circular(4)),
                ),
              ],
            ),
            const Divider(height: 20),

            // The three reported fields.
            _row('Product', record.productName),
            const SizedBox(height: 4),
            _row('Expiration date', record.expiration),
            const SizedBox(height: 10),
            LabelsPresentBadge(allPresent: record.allLabelsPresent),

            const Divider(height: 20),
            Text('INGREDIENTS',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted)),
            const SizedBox(height: 4),
            Text(record.ingredients, style: const TextStyle(fontSize: 13)),
            const Divider(height: 20),
            _row('Record name', name),
            const SizedBox(height: 4),
            _row('Date', _formatDate(record.scannedAt)),
            const Divider(height: 20),
            Text('Note : ${record.note}',
                style: TextStyle(fontSize: 12, color: record.noteColor)),
          ],
        ),
      ),
      if (record.reasons.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('WHY IT WAS FLAGGED',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.muted)),
        const SizedBox(height: 6),
        for (final reason in record.reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('•  $reason', style: const TextStyle(fontSize: 13)),
          ),
      ],
      const SizedBox(height: 16),
      _hotline(record.status == ComplianceStatus.compliant),
    ];
  }

  // ── Damage check report ────────────────────────────────────────────────────

  List<Widget> _damageSections(ScanRecord record) {
    final name = p.basename(widget.recordDir.path);

    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(record.damageIcon, color: record.damageColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(record.damageTitle,
                      style: TextStyle(
                          color: record.damageColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
              ],
            ),
            const Divider(height: 20),
            _row('Record name', name),
            const SizedBox(height: 4),
            _row('Date', _formatDate(record.scannedAt)),
            const SizedBox(height: 4),
            _row('Sides inspected', '${_boxPhotos.length} of 4'),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text('DAMAGE FOUND',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.muted)),
      const SizedBox(height: 6),
      DamageFindingsBlock(damage: record.damageCheck),
      const SizedBox(height: 16),
      _hotline(!record.damageCheck.isDamaged),
    ];
  }

  // ── Shared bits ────────────────────────────────────────────────────────────

  Widget _row(String label, String value) {
    return Text('$label : $value', style: const TextStyle(fontSize: 13));
  }

  Widget _hotline(bool clean) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        'FDA Hotline : (02) 8807-0751',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: clean ? Colors.black87 : const Color(0xFFE57373),
        ),
      ),
    );
  }
}

// ── Fullscreen photo viewer ─────────────────────────────────────────────────

class _FullscreenPhotoViewer extends StatelessWidget {
  final List<File> photos;
  final int initialIndex;

  const _FullscreenPhotoViewer({
    required this.photos,
    required this.initialIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: photos.length,
        itemBuilder: (context, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image.file(photos[i], fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
