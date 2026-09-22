import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/scan_record.dart';
import 'scan_store.dart';

/// Builds the Product Compliance Summary Report PDF.
///
/// The report covers exactly the records it is given — the Records screen
/// passes only what its active filters show — and every figure, table and
/// photo is derived from that one list.
///
/// Every record listed in the summary tables gets a matching entry in the
/// Scan Evidence section, tied together by a reference number (#1, #2, …),
/// so nothing appears on the first page without its evidence later on.
class ReportBuilder {
  // ── Colour palette matching the app's soft-green theme ──────────────────
  static const _green = PdfColor.fromInt(0xFF2E7D32);
  static const _greenLight = PdfColor.fromInt(0xFF4CAF50);
  static const _greenBg = PdfColor.fromInt(0xFFE8F5E9);
  static const _amber = PdfColor.fromInt(0xFFE65100);
  static const _amberBg = PdfColor.fromInt(0xFFFFF8E1);
  /// Records here come straight from stored JSON as raw status strings, so
  /// the warning check has to tolerate the pre-rename spellings too — see
  /// [ScanRecord.isWarningLabel].
  static bool _isWarning(String status) => ScanRecord.isWarningLabel(status);

  static const _red = PdfColor.fromInt(0xFFB71C1C);
  static const _redBg = PdfColor.fromInt(0xFFFFEBEE);
  static const _border = PdfColor.fromInt(0xFFC8E0CE);
  static const _muted = PdfColor.fromInt(0xFF6A8F6E);
  static const _text = PdfColor.fromInt(0xFF1A2E1C);
  static const _bg = PdfColor.fromInt(0xFFF0F7F2);
  static const _warningBg = PdfColor.fromInt(0xFFFFF8E1);
  static const _warningText = PdfColor.fromInt(0xFF5C4A1E);

  // Damage-box overlay: amber reads against cardboard without implying a
  // compliance verdict the way the report's red/green would.
  static const _boxStroke = PdfColor.fromInt(0xFFFFB300);
  static const _boxChip = PdfColor.fromInt(0xFFE65100);

  /// Largest box each evidence photo is drawn into, in points, and the pixel
  /// width the JPEG is downscaled to before embedding. Full-resolution
  /// captures would balloon the file for no visible gain at this print size.
  static const double _photoMaxWidth = 118;
  static const double _photoMaxHeight = 150;
  static const int _evidencePixelWidth = 480;

  /// Loads all record folders and their data.json files and builds the PDF.
  static Future<pw.Document> build() async {
    final dir = await ScanStore.rootDir();
    return buildFromDirs(_loadAllRecordDirs(dir));
  }

  /// Builds the report over an explicit set of record folders, in the order
  /// given — the Records screen passes its filtered, sorted list so the PDF
  /// matches what the user was looking at.
  ///
  /// [filterSummary] is printed in the header so a reader knows the report is
  /// a subset (e.g. "Type: Label · Status: Compliant · Date: 2025"). When
  /// [periodStart]/[periodEnd] are given (a date filter was active) the header
  /// shows that range instead of the span of the records' own dates.
  static Future<pw.Document> buildFromDirs(
    List<Directory> dirs, {
    String? filterSummary,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    final records = _parseRecords(dirs);
    final evidence = await _loadEvidence(records);
    return _buildDocument(
      records,
      evidence,
      filterSummary: filterSummary,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
  }

  // ── Record loading ───────────────────────────────────────────────────────

  static List<Directory> _loadAllRecordDirs(Directory dir) {
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<Directory>()
        .toList()
      ..sort((a, b) => b
          .statSync()
          .modified
          .compareTo(a.statSync().modified));
  }

  static List<_Record> _parseRecords(List<Directory> dirs) {
    var ref = 0;
    return dirs.map((d) {
      final record = ScanStore.load(d);
      return _Record(
        ref: ++ref,
        name: p.basename(d.path),
        date: record?.scannedAt ?? d.statSync().modified,
        status: record?.statusLabel ?? '—',
        keyword: record?.matchedKeyword ?? '—',
        dir: d,
        scan: record,
      );
    }).toList();
  }

  // ── Scan evidence ─────────────────────────────────────────────────────────

  static const _labelSlots = [
    PhotoSlot.front,
    PhotoSlot.expiration,
    PhotoSlot.ingredients,
  ];

  /// Loads and downscales the photos shown for each record, one entry per
  /// record in the same order (and with the same reference number) as the
  /// summary tables.
  ///
  /// Per record: its label close-ups, plus every packaging shot the damage
  /// detector drew boxes on. A clean damage-only scan has neither, so it gets
  /// its first packaging shot instead — otherwise it would be listed in the
  /// summary with nothing to show for it.
  ///
  /// Decoding is the expensive part, so this runs once up front rather than
  /// inside the page builder, which the pdf package may call more than once
  /// while it paginates.
  static Future<List<_RecordEvidence>> _loadEvidence(
      List<_Record> records) async {
    final out = <_RecordEvidence>[];

    for (final r in records) {
      final photos = <_Photo>[];

      for (final slot in _labelSlots) {
        final file = File(p.join(r.dir.path, '${slot.fileBaseName}.jpg'));
        if (!file.existsSync()) continue;
        final image = await _downscale(file);
        if (image == null) continue;
        photos.add(_Photo(
          image: image.image,
          aspect: image.aspect,
          caption: slot.timingLabel,
        ));
      }

      final boxPhotos = ScanStore.boxPhotosInOrder(r.dir);
      final damage = r.scan?.damageCheck;
      final byPhoto = <int, List<DamageDetection>>{};
      if (damage != null && damage.isDamaged) {
        for (final d in damage.boxes) {
          if (d.sourceIndex < 0 || d.sourceIndex >= boxPhotos.length) continue;
          byPhoto.putIfAbsent(d.sourceIndex, () => []).add(d);
        }
      }

      var indexes = byPhoto.keys.toList()..sort();
      if (indexes.isEmpty && photos.isEmpty && boxPhotos.isNotEmpty) {
        indexes = [0];
      }
      for (final index in indexes) {
        final file = boxPhotos[index];
        final image = await _downscale(file);
        if (image == null) continue;
        photos.add(_Photo(
          image: image.image,
          aspect: image.aspect,
          caption: _boxCaption(file),
          boxes: byPhoto[index] ?? const [],
        ));
      }

      out.add(_RecordEvidence(record: r, photos: photos));
    }
    return out;
  }

  static String _boxCaption(File file) {
    final base = p.basenameWithoutExtension(file.path);
    for (final slot in BoxSlot.values) {
      if (slot.fileBaseName == base) return 'Packaging: ${slot.label}';
    }
    return 'Packaging';
  }

  /// Re-encodes one photo down to [_evidencePixelWidth]. Returns null rather
  /// than throwing if the file is missing or won't decode — a report should
  /// still generate when one photo has gone bad.
  static Future<({pw.MemoryImage image, double aspect})?> _downscale(
      File file) async {
    try {
      final decoded = img.decodeImage(await file.readAsBytes());
      if (decoded == null) return null;
      // Bake orientation before measuring: the damage boxes were computed in
      // baked space, so a rotated capture would otherwise get a transposed
      // aspect ratio and boxes in the wrong places.
      final oriented = img.bakeOrientation(decoded);
      final resized = oriented.width > _evidencePixelWidth
          ? img.copyResize(oriented, width: _evidencePixelWidth)
          : oriented;
      if (resized.width == 0 || resized.height == 0) return null;
      return (
      image: pw.MemoryImage(img.encodeJpg(resized, quality: 80)),
      aspect: resized.width / resized.height,
      );
    } catch (_) {
      return null;
    }
  }

  static pw.Widget _statusChip(String status) {
    final (PdfColor fg, PdfColor bg, String label) = switch (status) {
      'COMPLIANT' => (_green, _greenBg, 'COMPLIANT'),
      'NON-COMPLIANT' => (_amber, _amberBg, 'NON-COMPLIANT'),
      _ when _isWarning(status) => (_red, _redBg, 'WARNING'),
      _ => (_muted, _bg, 'UNREADABLE'),
    };
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: pw.BoxDecoration(
        color: bg,
        border: pw.Border.all(color: fg, width: 0.6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Text(label,
          style: pw.TextStyle(
              fontSize: 7, fontWeight: pw.FontWeight.bold, color: fg)),
    );
  }

  static String _kindLabel(ScanRecord? scan) {
    if (scan == null) return 'Unknown check';
    final kind = switch (scan.kind) {
      ScanKind.label => 'Label check',
      ScanKind.damage => 'Damage check',
      ScanKind.both => 'Inspection (label + damage)',
    };
    final packaging = scan.packagingType?.label;
    return packaging == null ? kind : '$kind - $packaging';
  }

  /// One record's evidence: the same reference number, name, status and
  /// basis as its row on the first page, the reasons behind the verdict, and
  /// its photos (damage outlined where the detector found it).
  static pw.Widget _evidenceBlock(_RecordEvidence e) {
    final r = e.record;
    final scan = r.scan;
    final reasons = scan?.reasons ?? const <String>[];
    final damage = scan?.damageCheck;
    final showDamage =
        damage != null && scan!.hasDamageData && damage.isDamaged;

    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('#${r.ref}',
                  style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: _green)),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: pw.Text(
                  _pdfSafe(r.name),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: _text),
                ),
              ),
              pw.SizedBox(width: 6),
              _statusChip(r.status),
              pw.SizedBox(width: 6),
              pw.Text(_fmtDatetime(r.date),
                  style: pw.TextStyle(fontSize: 7.5, color: _muted)),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            _pdfSafe(r.keyword == '—' || r.keyword.isEmpty
                ? _kindLabel(scan)
                : '${_kindLabel(scan)}  -  Detection basis: ${r.keyword}'),
            style: pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
          if (scan == null) ...[
            pw.SizedBox(height: 3),
            pw.Text('The record\'s data file could not be read.',
                style: pw.TextStyle(fontSize: 7.5, color: _amber)),
          ],
          if (reasons.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            for (final reason in reasons.take(5))
              pw.Text(_pdfSafe('- $reason'),
                  maxLines: 2,
                  style: pw.TextStyle(fontSize: 7.5, color: _text)),
          ],
          if (showDamage) ...[
            pw.SizedBox(height: 4),
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
              decoration: pw.BoxDecoration(
                color: _boxChip,
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
              child: pw.Text(
                _pdfSafe(damage.detectionSummary),
                style: const pw.TextStyle(
                    fontSize: 6.5, color: PdfColor.fromInt(0xFFFFFFFF)),
              ),
            ),
          ],
          pw.SizedBox(height: 6),
          if (e.photos.isEmpty)
            pw.Text('No photos were saved with this record.',
                style: pw.TextStyle(fontSize: 7.5, color: _muted))
          else
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: e.photos.map(_photoCard).toList(),
            ),
        ],
      ),
    );
  }

  static pw.Widget _photoCard(_Photo photo) {
    // The boxes are fractions of the photo, so once the drawn size is fixed
    // every box scales by the same two numbers. Fit inside the max box while
    // keeping the photo's own aspect ratio so the boxes land square on it.
    var w = _photoMaxWidth;
    var h = w / photo.aspect;
    if (h > _photoMaxHeight) {
      h = _photoMaxHeight;
      w = h * photo.aspect;
    }

    return pw.SizedBox(
      width: _photoMaxWidth,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Stack(
            children: [
              pw.Image(photo.image, width: w, height: h),
              for (final d in photo.boxes)
                pw.Positioned(
                  left: d.left * w,
                  top: d.top * h,
                  child: pw.Container(
                    width: d.width * w,
                    height: d.height * h,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: _boxStroke, width: 1.2),
                    ),
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Text(_pdfSafe(photo.caption),
              style: pw.TextStyle(fontSize: 6.5, color: _muted)),
        ],
      ),
    );
  }

  // ── PDF construction ──────────────────────────────────────────────────────

  static pw.Document _buildDocument(
    List<_Record> records,
    List<_RecordEvidence> evidence, {
    String? filterSummary,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) {
    final doc = pw.Document();

    // Aggregate stats
    final total = records.length;
    final compliant =
        records.where((r) => r.status == 'COMPLIANT').length;
    final nonCompliant =
        records.where((r) => r.status == 'NON-COMPLIANT').length;
    final warning = records.where((r) => _isWarning(r.status)).length;

    final flagged = records
        .where((r) => r.status == 'NON-COMPLIANT' || _isWarning(r.status))
        .toList();

    // Common flag trigger frequency
    final triggerFreq = <String, int>{};
    for (final r in flagged) {
      if (r.keyword != '—' && r.keyword.isNotEmpty) {
        triggerFreq[r.keyword] = (triggerFreq[r.keyword] ?? 0) + 1;
      }
    }
    final sortedTriggers = triggerFreq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Date range
    final dates = records.map((r) => r.date).toList()..sort();
    final earliest = periodStart != null
        ? _fmtDate(periodStart)
        : dates.isNotEmpty
            ? _fmtDate(dates.first)
            : '-';
    final latest = periodEnd != null
        ? _fmtDate(periodEnd)
        : dates.isNotEmpty
            ? _fmtDate(dates.last)
            : '-';
    final compliantRecords =
        records.where((r) => r.status == 'COMPLIANT').toList();
    final unreadable = records.where((r) => r.scan == null).toList();
    final generated = _fmtDatetime(DateTime.now());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => [
          _header(generated, earliest, latest, filterSummary),
          pw.SizedBox(height: 16),
          _disclaimer(),
          pw.SizedBox(height: 20),
          _sectionTitle('Overview'),
          pw.SizedBox(height: 8),
          _overviewRow(total, compliant, nonCompliant, warning),
          pw.SizedBox(height: 20),
          _sectionTitle('Common Flag Triggers'),
          pw.SizedBox(height: 8),
          if (sortedTriggers.isEmpty)
            _emptyNote('No flagged records found.')
          else
            _triggerTable(sortedTriggers, flagged.length),
          pw.SizedBox(height: 20),
          _sectionTitle('Flagged Records'),
          pw.SizedBox(height: 8),
          if (flagged.isEmpty)
            _emptyNote('No flagged records.')
          else
            _flaggedTable(flagged),
          pw.SizedBox(height: 20),
          _sectionTitle('Compliant Products'),
          pw.SizedBox(height: 8),
          _compliantSection(compliantRecords),
          if (unreadable.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            _emptyNote(_pdfSafe(
                '${unreadable.length} record(s) could not be read and have no '
                'status: ${unreadable.map((r) => '#${r.ref} ${r.name}').join(', ')}. '
                'They are still listed under Scan Evidence.')),
          ],
          pw.SizedBox(height: 24),
          _hotlineFooter(),
          pw.NewPage(),
          _sectionTitle('Scan Evidence'),
          pw.SizedBox(height: 4),
          pw.Text(
            'One entry per record in this report, numbered to match the tables '
                'above. Damage the on-device detector found is outlined; '
                'percentages are model confidence, not a severity grade.',
            style: pw.TextStyle(fontSize: 8.5, color: _muted),
          ),
          pw.SizedBox(height: 8),
          if (evidence.isEmpty)
            _emptyNote('No records in this report.')
          else
            ...evidence.map(_evidenceBlock),
        ],
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated by CheckMuna',
                style: pw.TextStyle(fontSize: 9, color: _muted)),
            pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 9, color: _muted)),
          ],
        ),
      ),
    );

    return doc;
  }

  // ── Section builders ──────────────────────────────────────────────────────

  static pw.Widget _header(String generated, String earliest, String latest,
      String? filterSummary) {
    return pw.Container(
      width: double.infinity,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'CheckMuna',
            style: pw.TextStyle(
              fontSize: 28,
              fontWeight: pw.FontWeight.bold,
              color: _green,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Product Compliance Summary Report',
            style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: _text),
          ),
          pw.SizedBox(height: 6),
          pw.Divider(color: _greenLight, thickness: 1.5),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Generated: $generated',
                  style: pw.TextStyle(fontSize: 9, color: _muted)),
              pw.Text(_pdfSafe('Period: $earliest - $latest'),
                  style: pw.TextStyle(fontSize: 9, color: _muted)),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            _pdfSafe('Records included: '
                '${filterSummary == null || filterSummary.isEmpty ? 'All records' : filterSummary}'),
            style: pw.TextStyle(fontSize: 9, color: _muted),
          ),
        ],
      ),
    );
  }

  static pw.Widget _disclaimer() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _warningBg,
        border: pw.Border.all(color: PdfColor.fromInt(0xFFFFE082)),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Text(
        'This report is generated by CheckMuna based on automated label scanning and '
            'keyword-matching against FDA Philippines advisories. It is for informational '
            'purposes only and does not constitute an official FDA determination. To report '
            'a product, contact the FDA Philippines hotline listed at the end of this report.',
        style: pw.TextStyle(fontSize: 8.5, color: _warningText),
      ),
    );
  }

  static pw.Widget _sectionTitle(String title) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title,
            style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: _text)),
        pw.SizedBox(height: 3),
        pw.Divider(color: _border, thickness: 0.8),
      ],
    );
  }

  static pw.Widget _overviewRow(
      int total, int compliant, int nonCompliant, int warning) {
    return pw.Row(
      children: [
        _statBox('Total Scanned', '$total', _text, _bg),
        pw.SizedBox(width: 8),
        _statBox('Compliant', '$compliant', _green, _greenBg),
        pw.SizedBox(width: 8),
        _statBox('Non-Compliant', '$nonCompliant', _amber, _amberBg),
        pw.SizedBox(width: 8),
        _statBox('Warning', '$warning', _red, _redBg),
      ],
    );
  }

  static pw.Widget _statBox(
      String label, String value, PdfColor textColor, PdfColor bgColor) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: pw.BoxDecoration(
          color: bgColor,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          border: pw.Border.all(color: _border),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: textColor)),
            pw.SizedBox(height: 4),
            pw.Text(label,
                style: pw.TextStyle(fontSize: 8.5, color: _muted),
                textAlign: pw.TextAlign.center),
          ],
        ),
      ),
    );
  }

  static pw.Widget _triggerTable(
      List<MapEntry<String, int>> triggers, int totalFlagged) {
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(1.5),
        2: const pw.FlexColumnWidth(1.5),
        3: const pw.FlexColumnWidth(1.5),
      },
      children: [
        // Header
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _greenBg),
          children: [
            _tableCell('Keyword / Substance', header: true),
            _tableCell('Occurrences', header: true),
            _tableCell('% of Flagged', header: true),
            _tableCell('Status', header: true),
          ],
        ),
        ...triggers.map((e) {
          final pct = totalFlagged > 0
              ? '${(e.value / totalFlagged * 100).toStringAsFixed(0)}%'
              : '—';
          return pw.TableRow(children: [
            _tableCell(e.key),
            _tableCell('${e.value}'),
            _tableCell(pct),
            _tableCell('Flagged'),
          ]);
        }),
      ],
    );
  }

  static pw.Widget _flaggedTable(List<_Record> records) {
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(0.6),
        1: const pw.FlexColumnWidth(2.5),
        2: const pw.FlexColumnWidth(1.5),
        3: const pw.FlexColumnWidth(1.5),
        4: const pw.FlexColumnWidth(2.5),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _greenBg),
          children: [
            _tableCell('Ref', header: true),
            _tableCell('Product Name', header: true),
            _tableCell('Date Scanned', header: true),
            _tableCell('Status', header: true),
            _tableCell('Detection Basis', header: true),
          ],
        ),
        ...records.map((r) {
          final statusColor = _isWarning(r.status) ? _red : _amber;
          return pw.TableRow(children: [
            _tableCell('#${r.ref}'),
            _tableCell(r.name),
            _tableCell(_fmtDate(r.date)),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                _isWarning(r.status) ? 'WARNING' : 'NON-COMPLIANT',
                style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: statusColor),
              ),
            ),
            _tableCell(r.keyword),
          ]);
        }),
      ],
    );
  }

  static pw.Widget _compliantSection(List<_Record> records) {
    if (records.isEmpty) {
      return _emptyNote('No compliant records found.');
    }
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(0.6),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(1.5),
        3: const pw.FlexColumnWidth(2.5),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _greenBg),
          children: [
            _tableCell('Ref', header: true),
            _tableCell('Product Name', header: true),
            _tableCell('Date Scanned', header: true),
            _tableCell('Check', header: true),
          ],
        ),
        ...records.map((r) => pw.TableRow(children: [
              _tableCell('#${r.ref}'),
              _tableCell(r.name),
              _tableCell(_fmtDate(r.date)),
              _tableCell(_kindLabel(r.scan)),
            ])),
      ],
    );
  }

  static pw.Widget _hotlineFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _greenBg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('FDA Philippines',
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _green)),
          pw.SizedBox(height: 4),
          pw.Text(
            'Hotline: (02) 8807-0751  ·  Email: fdaphils@fda.gov.ph  ·  Site: www.fda.gov.ph\n'
                'If any product above is suspected to be dangerous or unregistered, please report it through the official FDA channel.',
            style: pw.TextStyle(fontSize: 8.5, color: _green),
          ),
        ],
      ),
    );
  }

  /// Every table cell carries record-supplied text (product names, matched
  /// keywords, the '-' placeholder for a missing field), so the ASCII fold
  /// belongs here rather than at each call site.
  static pw.Widget _tableCell(String text, {bool header = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        _pdfSafe(text),
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: _text,
        ),
      ),
    );
  }

  static pw.Widget _emptyNote(String msg) {
    return pw.Text(msg,
        style: pw.TextStyle(fontSize: 9, color: _muted));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Maps the typographic characters the app uses onto ASCII before they are
  /// drawn into the PDF.
  ///
  /// The pdf package's built-in Helvetica is a Latin-1 font with no Unicode
  /// coverage, so an em dash, en dash or multiplication sign silently draws
  /// as nothing — the record name reads "Dent 2" instead of "Dent x2", and a
  /// missing field renders as blank rather than a dash. Rather than bundle a
  /// full Unicode font just for four characters, fold them here; the on-screen
  /// text keeps the nicer glyphs.
  static String _pdfSafe(String s) => s
      .replaceAll('×', 'x') // multiplication sign
      .replaceAll('—', '-') // em dash
      .replaceAll('–', '-') // en dash
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll('“', '"')
      .replaceAll('”', '"');

  static String _fmtDate(DateTime dt) =>
      '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';

  static String _fmtDatetime(DateTime dt) =>
      '${_fmtDate(dt)}  ${_pad(dt.hour)}:${_pad(dt.minute)}';

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

// ── Internal model ────────────────────────────────────────────────────────────

/// One photo in a record's evidence entry, ready to draw.
class _Photo {
  final pw.MemoryImage image;

  /// Width / height of the embedded photo, used to give the drawn image a
  /// height that matches it so the normalised boxes land square on it.
  final double aspect;
  final String caption;

  /// Damage boxes on this photo; empty for label close-ups and clean shots.
  final List<DamageDetection> boxes;

  const _Photo({
    required this.image,
    required this.aspect,
    required this.caption,
    this.boxes = const [],
  });
}

/// A record's evidence entry: the record plus the photos drawn for it.
class _RecordEvidence {
  final _Record record;
  final List<_Photo> photos;

  const _RecordEvidence({required this.record, required this.photos});
}

class _Record {
  /// 1-based position in the report. Printed in the summary tables and on the
  /// record's evidence entry so the two can be matched up.
  final int ref;
  final String name;
  final DateTime date;
  final String status;
  final String keyword;
  final Directory dir;

  /// The parsed record, or null if its data.json was missing or unreadable —
  /// the row still lists in the tables above from folder metadata alone.
  final ScanRecord? scan;

  const _Record({
    required this.ref,
    required this.name,
    required this.date,
    required this.status,
    required this.keyword,
    required this.dir,
    this.scan,
  });
}