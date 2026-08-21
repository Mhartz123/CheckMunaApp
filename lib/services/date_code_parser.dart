import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_geometry.dart';

/// Outcome of reading a date code.
///
/// [unreadable] is emphatically not the same thing as "no expiry problem". It
/// mirrors the `available = false` vs `is_damaged = false` distinction already
/// drawn on the damage side: conflating the two inflates the clean counts and
/// lets an unread code pass as fresh. Callers must handle it as its own
/// outcome, never as a pass.
enum DateCodeStatus { parsed, unreadable, ambiguous }

class DateCode {
  final DateTime? manufactured;

  /// Last day the product is in date. Month-precision codes resolve to the
  /// last day of the printed month, matching the existing expiry semantics.
  final DateTime? expiry;

  final String? batch;
  final DateCodeStatus status;

  /// Why the read is unreadable or ambiguous, for the report.
  final String? note;

  const DateCode({
    this.manufactured,
    this.expiry,
    this.batch,
    required this.status,
    this.note,
  });
}

/// Vertical grouping tolerance for reading order, as a fraction of the median
/// line height. Overprinted values drift off the pre-printed baseline grid, so
/// the buckets have to be looser than a line height.
const double kReadingOrderBucketFactor = 0.7;

/// How far from a label a value may sit, in label heights, for the proximity
/// fallback to accept it.
const double kProximityLineHeights = 1.5;

/// Plausible shelf life. A misread digit usually breaks one of these bounds,
/// which turns a silently wrong answer into a caught error.
const int kMinShelfLifeMonths = 6;
const int kMaxShelfLifeMonths = 72;
const int kMaxExpiryYearsAhead = 10;

/// Glyphs ML Kit routinely confuses for digits in a date context.
///
/// Applied to date tokens only. A real batch code looks like `B.177T78`, where
/// the `B` and the `T` are genuine letters — a blanket pass over the whole
/// crop fixes the dates and corrupts the batch number in the same sweep.
const Map<String, String> kDigitLookalikes = <String, String>{
  'O': '0',
  'I': '1',
  'l': '1',
  '|': '1',
  'S': '5',
  'B': '8',
  'Z': '2',
  'G': '6',
  'T': '7',
  'D': '0',
};

/// Reads manufacture/expiry dates and a batch code out of ML Kit's output for
/// the date-code crop.
class DateCodeParser {
  const DateCodeParser._();

  // Anchors are matched against the raw text, never the normalized text: the
  // digit map would turn MFG into MF6 and Batch into 8a7ch. The negative
  // lookahead lets EXP match "EXP03/2028" (no word boundary between P and 0)
  // while still rejecting EXPORT, and the longer spellings come first so they
  // are not shadowed by the short one.
  static final RegExp _mfgAnchor =
      RegExp(r'\b(?:MFG|MFD)(?![A-Za-z])', caseSensitive: false);
  static final RegExp _expAnchor =
      RegExp(r'\b(?:EXPIRY|EXPIRATION|EXP)(?![A-Za-z])', caseSensitive: false);
  static final RegExp _batchAnchor =
      RegExp(r'\b(?:BATCH|LOT)(?![A-Za-z])', caseSensitive: false);

  // Longest first; each match consumes its span so a DD/MM/YYYY reading is
  // never re-read as the MM/YYYY sitting inside it.
  static final RegExp _dayMonthYear = RegExp(
      r'(?<!\d)(0[1-9]|[12]\d|3[01])\s*[/\-.]\s*(0[1-9]|1[0-2])\s*[/\-.]\s*(20\d{2})(?!\d)');
  static final RegExp _monthYear =
      RegExp(r'(?<!\d)(0[1-9]|1[0-2])\s*[/\-.]\s*(20\d{2})(?!\d)');
  static final RegExp _monthShortYear =
      RegExp(r'(?<!\d)(0[1-9]|1[0-2])\s*[/\-.]\s*(\d{2})(?!\d)');

  /// A batch code: at least four characters of alphanumerics and separators,
  /// carrying at least one digit. Read off the raw text with the label and
  /// date spans blanked out.
  static final RegExp _batchCandidate = RegExp(r'[A-Za-z0-9][A-Za-z0-9./\-]{3,}');

  /// Parses the date code out of [recognized].
  ///
  /// [today] is injectable so the "not more than [kMaxExpiryYearsAhead] years
  /// ahead" check is deterministic under test.
  static DateCode parse(
    RecognizedText recognized, {
    double maxSkewDegrees = kDateCodeMaxSkewDegrees,
    DateTime? today,
  }) {
    final lines =
        OcrGeometry.horizontalLines(recognized, maxSkewDegrees: maxSkewDegrees);
    return parseLines(lines, today: today);
  }

  /// As [parse], for callers that have already filtered the lines.
  static DateCode parseLines(List<TextLine> lines, {DateTime? today}) {
    final ordered = _readingOrder(lines);

    final anchors = <_Anchor>[];
    final tokens = <_DateToken>[];
    final batches = <_BatchCandidate>[];
    for (var i = 0; i < ordered.length; i++) {
      _scanLine(ordered[i], i, anchors, tokens, batches);
    }
    anchors.sort(_byReadingPosition);
    tokens.sort(_byReadingPosition);

    final batch = _pickBatch(anchors, batches);
    final dateAnchors = anchors
        .where((a) => a.kind != _AnchorKind.batch)
        .toList(growable: false);

    _DateToken? manufacturedToken;
    _DateToken? expiryToken;
    var status = DateCodeStatus.parsed;
    String? note;

    if (dateAnchors.isNotEmpty && dateAnchors.length == tokens.length) {
      // Zip in reading order. This is the case that matters: when an
      // overprinted value sits on a different baseline grid from its
      // pre-printed label, nearest-baseline association binds it to the
      // neighbouring label and reports an expired product as fresh. Ordinal
      // position survives the drift; vertical distance does not.
      for (var i = 0; i < dateAnchors.length; i++) {
        if (dateAnchors[i].kind == _AnchorKind.mfg) {
          manufacturedToken ??= tokens[i];
        } else {
          expiryToken ??= tokens[i];
        }
      }
    } else if (dateAnchors.isNotEmpty) {
      status = DateCodeStatus.ambiguous;
      note = 'Date labels and values did not line up; matched by proximity.';
      for (final anchor in dateAnchors) {
        final token = _nearestToken(anchor, tokens);
        if (token == null) continue;
        if (anchor.kind == _AnchorKind.mfg) {
          manufacturedToken ??= token;
        } else {
          expiryToken ??= token;
        }
      }
    } else if (tokens.length == 2) {
      final sorted = List<_DateToken>.of(tokens)
        ..sort((a, b) => a.asExpiry.compareTo(b.asExpiry));
      manufacturedToken = sorted.first;
      expiryToken = sorted.last;
    } else if (tokens.length == 1) {
      // The most common single marking on a pack is the expiry, but it is a
      // guess and has to be reported as one.
      expiryToken = tokens.first;
      status = DateCodeStatus.ambiguous;
      note = 'Single unlabelled date read; assumed to be the expiry.';
    } else if (tokens.length > 2) {
      final sorted = List<_DateToken>.of(tokens)
        ..sort((a, b) => a.asExpiry.compareTo(b.asExpiry));
      manufacturedToken = sorted.first;
      expiryToken = sorted.last;
      status = DateCodeStatus.ambiguous;
      note = '${tokens.length} unlabelled dates read; '
          'assumed the earliest and latest.';
    }

    return _validate(
      manufactured: manufacturedToken?.asManufactured,
      expiry: expiryToken?.asExpiry,
      batch: batch,
      status: status,
      note: note,
      today: today ?? DateTime.now(),
    );
  }

  // ── Structural validation ────────────────────────────────────────────────

  /// Cross-checks the pair and fails loudly. A misread digit usually breaks
  /// one of these, so the check converts a silently wrong date into a caught
  /// error. On failure both dates are dropped rather than one, so an
  /// [DateCodeStatus.unreadable] result can never be mistaken for a usable
  /// reading.
  static DateCode _validate({
    required DateTime? manufactured,
    required DateTime? expiry,
    required String? batch,
    required DateCodeStatus status,
    required String? note,
    required DateTime today,
  }) {
    DateCode unreadable(String why) =>
        DateCode(batch: batch, status: DateCodeStatus.unreadable, note: why);

    if (manufactured == null && expiry == null) {
      return unreadable(note ?? 'No readable date code found.');
    }

    if (expiry == null) {
      return unreadable(
          'A manufacture date was read but no expiry date was found.');
    }

    final horizon =
        DateTime(today.year + kMaxExpiryYearsAhead, today.month, today.day);
    if (expiry.isAfter(horizon)) {
      return unreadable('Expiry reads more than $kMaxExpiryYearsAhead years '
          'ahead, so at least one digit was misread.');
    }

    if (manufactured != null) {
      if (!expiry.isAfter(manufactured)) {
        return unreadable(
            'Expiry date is not after the manufacture date, so the two were '
            'misread or swapped.');
      }
      final months = (expiry.year * 12 + expiry.month) -
          (manufactured.year * 12 + manufactured.month);
      if (months < kMinShelfLifeMonths || months > kMaxShelfLifeMonths) {
        return unreadable('Gap of $months months between manufacture and '
            'expiry is outside the plausible $kMinShelfLifeMonths-'
            '$kMaxShelfLifeMonths month shelf life.');
      }
    }

    return DateCode(
      manufactured: manufactured,
      expiry: expiry,
      batch: batch,
      status: status,
      note: note,
    );
  }

  // ── Line scanning ────────────────────────────────────────────────────────

  static void _scanLine(
    TextLine line,
    int index,
    List<_Anchor> anchors,
    List<_DateToken> tokens,
    List<_BatchCandidate> batches,
  ) {
    final raw = line.text;
    if (raw.isEmpty) return;
    final box = line.boundingBox;

    // Spans already claimed by a label or a date. Blanking them keeps each
    // pass from re-reading what an earlier one already accounted for.
    final claimed = List<bool>.filled(raw.length, false);
    void claim(int start, int end) {
      for (var i = start; i < end && i < claimed.length; i++) {
        claimed[i] = true;
      }
    }

    const anchorPatterns = <_AnchorKind>[
      _AnchorKind.mfg,
      _AnchorKind.exp,
      _AnchorKind.batch,
    ];
    for (final kind in anchorPatterns) {
      for (final match in _anchorPattern(kind).allMatches(raw)) {
        anchors.add(_Anchor(kind, index, match.start, box));
        claim(match.start, match.end);
      }
    }

    // Digit normalization applies to what is left after the labels are
    // removed, so MFG cannot contribute a stray 6 to the digits beside it.
    final masked = _mask(raw, claimed);
    final normalized = _normalizeDigits(masked);

    for (final pattern in <RegExp>[
      _dayMonthYear,
      _monthYear,
      _monthShortYear,
    ]) {
      for (final match in pattern.allMatches(normalized)) {
        if (_anyClaimed(claimed, match.start, match.end)) continue;
        final token = _tokenFrom(pattern, match, index, box);
        if (token == null) continue;
        tokens.add(token);
        claim(match.start, match.end);
      }
    }

    // Batch candidates come off the raw text, never the normalized text.
    for (final match in _batchCandidate.allMatches(_mask(raw, claimed))) {
      final text = match.group(0)!;
      if (!text.contains(RegExp(r'\d'))) continue;
      batches.add(_BatchCandidate(text, index, match.start, box));
    }
  }

  static RegExp _anchorPattern(_AnchorKind kind) => switch (kind) {
        _AnchorKind.mfg => _mfgAnchor,
        _AnchorKind.exp => _expAnchor,
        _AnchorKind.batch => _batchAnchor,
      };

  static String _mask(String source, List<bool> claimed) {
    final buffer = StringBuffer();
    for (var i = 0; i < source.length; i++) {
      buffer.write(claimed[i] ? ' ' : source[i]);
    }
    return buffer.toString();
  }

  static bool _anyClaimed(List<bool> claimed, int start, int end) {
    for (var i = start; i < end && i < claimed.length; i++) {
      if (claimed[i]) return true;
    }
    return false;
  }

  /// Substitutes digit lookalikes one for one, so offsets into the result
  /// still line up with the raw text.
  static String _normalizeDigits(String source) {
    final buffer = StringBuffer();
    for (var i = 0; i < source.length; i++) {
      final ch = source[i];
      buffer.write(kDigitLookalikes[ch] ?? ch);
    }
    return buffer.toString();
  }

  static _DateToken? _tokenFrom(
    RegExp pattern,
    RegExpMatch match,
    int lineIndex,
    Rect box,
  ) {
    if (pattern == _dayMonthYear) {
      final day = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final year = int.parse(match.group(3)!);
      if (day > _daysInMonth(year, month)) return null;
      return _DateToken(year, month, day, lineIndex, match.start, box);
    }
    if (pattern == _monthYear) {
      return _DateToken(int.parse(match.group(2)!), int.parse(match.group(1)!),
          null, lineIndex, match.start, box);
    }
    // MM/YY, expanded into the 2000s.
    return _DateToken(2000 + int.parse(match.group(2)!),
        int.parse(match.group(1)!), null, lineIndex, match.start, box);
  }

  static int _daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  // ── Reading order ────────────────────────────────────────────────────────

  /// Sorts [lines] into reading order: grouped into rows by vertical position,
  /// then left to right within each row.
  ///
  /// Rows are grown greedily against a tolerance derived from the median line
  /// height rather than cut on a fixed grid, because an overprinted value can
  /// sit most of a line height away from the label it belongs to and a fixed
  /// grid would drop it into the wrong row. The zip in [parseLines] only needs
  /// relative vertical order to survive, which this preserves either way.
  static List<TextLine> _readingOrder(List<TextLine> lines) {
    if (lines.length < 2) return List<TextLine>.of(lines);

    final heights = <double>[for (final line in lines) line.boundingBox.height]
      ..sort();
    final median = heights[heights.length ~/ 2];
    final tolerance = (median <= 0 ? 1.0 : median) * kReadingOrderBucketFactor;

    final sorted = List<TextLine>.of(lines)
      ..sort((a, b) =>
          a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy));

    final ordered = <TextLine>[];
    var row = <TextLine>[];
    var rowAnchor = sorted.first.boundingBox.center.dy;

    void flush() {
      row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      ordered.addAll(row);
      row = <TextLine>[];
    }

    for (final line in sorted) {
      final y = line.boundingBox.center.dy;
      if (row.isNotEmpty && (y - rowAnchor).abs() > tolerance) {
        flush();
        rowAnchor = y;
      }
      row.add(line);
    }
    flush();
    return ordered;
  }

  static int _byReadingPosition(_Positioned a, _Positioned b) {
    final byLine = a.lineIndex.compareTo(b.lineIndex);
    return byLine != 0 ? byLine : a.offset.compareTo(b.offset);
  }

  // ── Fallback association ─────────────────────────────────────────────────

  /// Nearest token to the right of [anchor] and within
  /// [kProximityLineHeights] label heights of it.
  static _DateToken? _nearestToken(_Anchor anchor, List<_DateToken> tokens) {
    final height = anchor.box.height <= 0 ? 1.0 : anchor.box.height;
    final limit = height * kProximityLineHeights;
    _DateToken? best;
    var bestDistance = double.infinity;

    for (final token in tokens) {
      final sameLine = token.lineIndex == anchor.lineIndex;
      final rightOfAnchor = sameLine
          ? token.offset > anchor.offset
          : token.box.left >= anchor.box.left;
      if (!rightOfAnchor) continue;

      final distance =
          (token.box.center.dy - anchor.box.center.dy).abs();
      if (distance > limit) continue;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = token;
      }
    }
    return best;
  }

  static String? _pickBatch(
    List<_Anchor> anchors,
    List<_BatchCandidate> candidates,
  ) {
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first.text;

    final batchAnchors =
        anchors.where((a) => a.kind == _AnchorKind.batch).toList();
    if (batchAnchors.isEmpty) return null;

    final anchor = batchAnchors.first;
    final height = anchor.box.height <= 0 ? 1.0 : anchor.box.height;
    final limit = height * kProximityLineHeights;
    _BatchCandidate? best;
    var bestDistance = double.infinity;
    for (final candidate in candidates) {
      final distance =
          (candidate.box.center.dy - anchor.box.center.dy).abs();
      if (distance > limit) continue;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    return best?.text;
  }
}

enum _AnchorKind { mfg, exp, batch }

/// Anything carrying a position in reading order.
abstract class _Positioned {
  int get lineIndex;
  int get offset;
}

class _Anchor implements _Positioned {
  final _AnchorKind kind;
  @override
  final int lineIndex;
  @override
  final int offset;
  final Rect box;

  const _Anchor(this.kind, this.lineIndex, this.offset, this.box);
}

class _DateToken implements _Positioned {
  final int year;
  final int month;

  /// Null for a month-precision code such as `03/2028`.
  final int? day;

  @override
  final int lineIndex;
  @override
  final int offset;
  final Rect box;

  const _DateToken(
    this.year,
    this.month,
    this.day,
    this.lineIndex,
    this.offset,
    this.box,
  );

  /// A month-precision manufacture date starts on the first of the month.
  DateTime get asManufactured => DateTime(year, month, day ?? 1);

  /// A month-precision expiry runs to the last day of the month, matching the
  /// cutoff semantics the compliance check already uses.
  DateTime get asExpiry =>
      day != null ? DateTime(year, month, day!) : DateTime(year, month + 1, 0);
}

class _BatchCandidate implements _Positioned {
  final String text;
  @override
  final int lineIndex;
  @override
  final int offset;
  final Rect box;

  const _BatchCandidate(this.text, this.lineIndex, this.offset, this.box);
}
